// ladderRoutes.js
// Standalone ladder mode — a persistent, always-on ranked list per
// sport+city, fully separate from user_sports.rating (see
// migration_ladder.sql's header for why). Mirrors friendlyRoutes.js's
// shape wherever the shape matches (helpers, notification pattern,
// RouteError/transaction usage); diverges where ladder stakes genuinely
// differ — a ladder result moves your rank, so reporting follows
// matches.js's self-report -> other-player-confirms shape instead of
// friendly matches' "whoever reports is final" shortcut.
//
// Singles only for v1 — same reasoning as friendly matches: a doubles
// ladder needs its own pair-matchmaking problem, a natural v2.
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { RouteError } = pool;
const { createNotification, createNotifications } = require('./notifications');
const { isBlockedEitherWay } = require('./blocking');

// How far above your own position you're allowed to challenge — the
// standard ladder rule, stops a brand-new #50 player directly challenging
// #1. Adjustable later if it turns out to be too tight/loose in practice.
const CHALLENGE_RANGE = 5;
// How long after any resolved challenge between the same pair before they
// can challenge each other again — anti-spam, same spirit as friendly
// matches' duplicate-pending-challenge guard.
const RECHALLENGE_COOLDOWN_DAYS = 3;

// Same small validators matchRoutes.js/friendlyRoutes.js have — kept as a
// local copy per this codebase's convention of duplicating small per-file
// helpers rather than sharing a module for a narrow check (see CLAUDE.md).
const MAX_PLAUSIBLE_UNITS = 500;

function isValidUnitCount(value) {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= MAX_PLAUSIBLE_UNITS;
}

function isValidSetScores(setScores) {
  if (setScores == null) return true;
  if (!Array.isArray(setScores)) return false;
  return setScores.every((s) => {
    if (s == null || typeof s !== 'object') return false;
    if (!isValidUnitCount(s.me) || !isValidUnitCount(s.opponent)) return false;
    return s.me !== s.opponent;
  });
}

function winnerUnitsAreConsistent(winnerIsChallenger, challengerUnits, defenderUnits) {
  return winnerIsChallenger ? challengerUnits > defenderUnits : defenderUnits > challengerUnits;
}

// ---------- VIEW A LADDER'S STANDINGS ----------
router.get('/:sport', async (req, res) => {
  const { sport } = req.params;
  const { city } = req.query;

  if (!city) {
    return res.status(400).json({ error: 'City is required.' });
  }

  try {
    const result = await pool.query(
      `SELECT lm.user_id, lm.position, lm.joined_at, u.username, us.rating
       FROM ladder_members lm
       JOIN users u ON u.id = lm.user_id
       LEFT JOIN user_sports us ON us.user_id = lm.user_id AND us.sport = lm.sport AND us.format = 'singles'
       WHERE lm.sport = $1 AND lm.city = $2
       ORDER BY lm.position ASC`,
      [sport, city]
    );
    res.status(200).json({ members: result.rows });
  } catch (err) {
    console.error('Get ladder error:', err);
    res.status(500).json({ error: 'Something went wrong fetching the ladder.' });
  }
});

// ---------- JOIN A LADDER ----------
router.post('/join', async (req, res) => {
  const userId = req.userId;
  const { sport, city } = req.body;

  if (!sport || !city) {
    return res.status(400).json({ error: 'Sport and city are required.' });
  }

  try {
    const sportResult = await pool.query(
      `SELECT 1 FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = 'singles'`,
      [userId, sport]
    );
    if (sportResult.rows.length === 0) {
      return res.status(400).json({ error: 'Add this sport to your profile first — you need a rating to join a ladder.' });
    }

    const existing = await pool.query(
      'SELECT 1 FROM ladder_members WHERE user_id = $1 AND sport = $2 AND city = $3',
      [userId, sport, city]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: "You're already on this ladder." });
    }

    const maxResult = await pool.query(
      'SELECT COALESCE(MAX(position), 0) AS max_position FROM ladder_members WHERE sport = $1 AND city = $2',
      [sport, city]
    );
    const nextPosition = maxResult.rows[0].max_position + 1;

    await pool.query(
      'INSERT INTO ladder_members (user_id, sport, city, position) VALUES ($1, $2, $3, $4)',
      [userId, sport, city, nextPosition]
    );

    res.status(201).json({ position: nextPosition });
  } catch (err) {
    console.error('Join ladder error:', err);
    res.status(500).json({ error: 'Something went wrong joining the ladder.' });
  }
});

// ---------- LEAVE A LADDER ----------
router.delete('/leave', async (req, res) => {
  const userId = req.userId;
  const { sport, city } = req.body;

  if (!sport || !city) {
    return res.status(400).json({ error: 'Sport and city are required.' });
  }

  try {
    await pool.withTransaction(async (client) => {
      const result = await client.query(
        'SELECT position FROM ladder_members WHERE user_id = $1 AND sport = $2 AND city = $3 FOR UPDATE',
        [userId, sport, city]
      );
      if (result.rows.length === 0) {
        throw new RouteError(404, "You're not on this ladder.");
      }
      const { position } = result.rows[0];

      await client.query(
        'DELETE FROM ladder_members WHERE user_id = $1 AND sport = $2 AND city = $3',
        [userId, sport, city]
      );
      // Close the gap so the ladder stays contiguous.
      await client.query(
        'UPDATE ladder_members SET position = position - 1 WHERE sport = $1 AND city = $2 AND position > $3',
        [sport, city, position]
      );
    });

    res.status(200).json({ message: 'Left the ladder.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Leave ladder error:', err);
    res.status(500).json({ error: 'Something went wrong leaving the ladder.' });
  }
});

// ---------- SEND A LADDER CHALLENGE ----------
router.post('/challenge', async (req, res) => {
  const userId = req.userId;
  const { sport, city, proposedTime, venue } = req.body;
  const defenderId = req.body.defenderId != null ? parseInt(req.body.defenderId, 10) : null;

  if (!sport || !city || !defenderId) {
    return res.status(400).json({ error: 'Sport, city, and an opponent are required.' });
  }
  if (defenderId === userId) {
    return res.status(400).json({ error: "You can't challenge yourself." });
  }

  try {
    if (await isBlockedEitherWay(pool, userId, defenderId)) {
      return res.status(403).json({ error: "You can't challenge this player." });
    }

    const membersResult = await pool.query(
      'SELECT user_id, position FROM ladder_members WHERE sport = $1 AND city = $2 AND user_id = ANY($3::int[])',
      [sport, city, [userId, defenderId]]
    );
    const challengerRow = membersResult.rows.find((r) => r.user_id === userId);
    const defenderRow = membersResult.rows.find((r) => r.user_id === defenderId);
    if (!challengerRow) {
      return res.status(400).json({ error: 'Join this ladder before challenging someone on it.' });
    }
    if (!defenderRow) {
      return res.status(404).json({ error: 'That player is not on this ladder.' });
    }
    if (defenderRow.position >= challengerRow.position) {
      return res.status(400).json({ error: 'You can only challenge a player ranked above you.' });
    }
    if (challengerRow.position - defenderRow.position > CHALLENGE_RANGE) {
      return res.status(400).json({ error: `You can only challenge up to ${CHALLENGE_RANGE} positions above you.` });
    }

    const existing = await pool.query(
      `SELECT * FROM ladder_challenges
       WHERE sport = $1 AND city = $2
         AND ((challenger_id = $3 AND defender_id = $4) OR (challenger_id = $4 AND defender_id = $3))
         AND status IN ('pending', 'accepted', 'reported')`,
      [sport, city, userId, defenderId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'There is already an open challenge between you and this player.' });
    }

    const cooldownResult = await pool.query(
      `SELECT 1 FROM ladder_challenges
       WHERE sport = $1 AND city = $2
         AND ((challenger_id = $3 AND defender_id = $4) OR (challenger_id = $4 AND defender_id = $3))
         AND status IN ('confirmed', 'declined', 'cancelled')
         AND updated_at > NOW() - INTERVAL '${RECHALLENGE_COOLDOWN_DAYS} days'`,
      [sport, city, userId, defenderId]
    );
    if (cooldownResult.rows.length > 0) {
      return res.status(429).json({ error: `You can challenge this player again in a few days — challenges between the same two players are limited to once every ${RECHALLENGE_COOLDOWN_DAYS} days.` });
    }

    const result = await pool.query(
      `INSERT INTO ladder_challenges (sport, city, challenger_id, defender_id, status, proposed_time, venue)
       VALUES ($1, $2, $3, $4, 'pending', $5, $6)
       RETURNING *`,
      [sport, city, userId, defenderId, proposedTime || null, venue || null]
    );
    const challenge = result.rows[0];

    await createNotification(pool, {
      userId: defenderId,
      type: 'ladder_challenge',
      title: 'Ladder challenge',
      body: `You've been challenged on the ${city} ${sport.replace('_', ' ')} ladder.`,
    });

    res.status(201).json({ challenge });
  } catch (err) {
    console.error('Send ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong sending the challenge.' });
  }
});

// ---------- MY PENDING / IN-PROGRESS LADDER CHALLENGES ----------
router.get('/challenges/pending', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT lc.*, c.username AS challenger_username, d.username AS defender_username
       FROM ladder_challenges lc
       JOIN users c ON c.id = lc.challenger_id
       JOIN users d ON d.id = lc.defender_id
       WHERE (lc.challenger_id = $1 OR lc.defender_id = $1)
         AND lc.status IN ('pending', 'accepted', 'reported')
       ORDER BY lc.created_at DESC`,
      [userId]
    );

    const incoming = result.rows.filter((r) => r.status === 'pending' && r.defender_id === userId);
    const outgoing = result.rows.filter((r) => r.status === 'pending' && r.challenger_id === userId);
    const accepted = result.rows.filter((r) => r.status === 'accepted');
    // Reported by the other player — I'm the one who needs to confirm/dispute.
    const awaitingMyConfirmation = result.rows.filter(
      (r) => r.status === 'reported' && r.reported_by !== userId
    );
    // Reported by me — waiting on the other player.
    const awaitingTheirConfirmation = result.rows.filter(
      (r) => r.status === 'reported' && r.reported_by === userId
    );

    res.status(200).json({ incoming, outgoing, accepted, awaitingMyConfirmation, awaitingTheirConfirmation });
  } catch (err) {
    console.error('Get pending ladder challenges error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your ladder challenges.' });
  }
});

// ---------- ACCEPT / DECLINE A CHALLENGE ----------
router.post('/:id/respond', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;
  const { accept } = req.body;

  try {
    let newStatus, challengerId;

    await pool.withTransaction(async (client) => {
      const result = await client.query('SELECT * FROM ladder_challenges WHERE id = $1 FOR UPDATE', [challengeId]);
      if (result.rows.length === 0) {
        throw new RouteError(404, 'Challenge not found.');
      }
      const challenge = result.rows[0];

      if (challenge.defender_id !== userId) {
        throw new RouteError(403, 'Only the challenged player can respond to this.');
      }
      if (challenge.status !== 'pending') {
        throw new RouteError(409, 'This challenge has already been responded to.');
      }

      newStatus = accept === true ? 'accepted' : 'declined';
      challengerId = challenge.challenger_id;

      await client.query(
        `UPDATE ladder_challenges SET status = $1, updated_at = NOW() WHERE id = $2 AND status = 'pending'`,
        [newStatus, challengeId]
      );

      await createNotification(client, {
        userId: challengerId,
        type: 'ladder_response',
        title: accept === true ? 'Ladder challenge accepted' : 'Ladder challenge declined',
        body: accept === true
          ? 'Your ladder challenge was accepted — coordinate a time to play!'
          : 'Your ladder challenge was declined.',
      });
    });

    res.status(200).json({ message: `Challenge ${newStatus}.` });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Respond to ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong responding to the challenge.' });
  }
});

// ---------- REPORT A RESULT ----------
// Unlike a friendly match, this doesn't finalize immediately — a ladder
// result moves your rank, so the other player must confirm (or dispute)
// before positions actually move. See POST /:id/confirm.
router.post('/:id/report', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;
  const { player1Units, player2Units, setScores, winnerId } = req.body;

  if (player1Units == null || player2Units == null || winnerId == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isValidUnitCount(player1Units) || !isValidUnitCount(player2Units)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }

  try {
    await pool.withTransaction(async (client) => {
      const result = await client.query('SELECT * FROM ladder_challenges WHERE id = $1 FOR UPDATE', [challengeId]);
      if (result.rows.length === 0) {
        throw new RouteError(404, 'Challenge not found.');
      }
      const challenge = result.rows[0];

      if (challenge.challenger_id !== userId && challenge.defender_id !== userId) {
        throw new RouteError(403, 'Only the two players in this challenge can report a result.');
      }
      if (challenge.status !== 'accepted') {
        throw new RouteError(409, 'This challenge needs to be accepted before a result can be reported.');
      }
      if (winnerId !== challenge.challenger_id && winnerId !== challenge.defender_id) {
        throw new RouteError(400, 'Winner must be one of the two players.');
      }
      // player1Units/player2Units always refer to challenger/defender
      // respectively, regardless of who's doing the reporting.
      if (!winnerUnitsAreConsistent(winnerId === challenge.challenger_id, player1Units, player2Units)) {
        throw new RouteError(400, "The declared winner's score must be higher than the opponent's.");
      }

      await client.query(
        `UPDATE ladder_challenges
         SET player1_units = $1, player2_units = $2, set_scores = $3, winner_id = $4,
             reported_by = $5, status = 'reported', updated_at = NOW()
         WHERE id = $6 AND status = 'accepted'`,
        [player1Units, player2Units, JSON.stringify(setScores || []), winnerId, userId, challengeId]
      );

      const otherPlayerId = userId === challenge.challenger_id ? challenge.defender_id : challenge.challenger_id;
      await createNotification(client, {
        userId: otherPlayerId,
        type: 'ladder_report',
        title: 'Ladder result reported',
        body: 'A result was reported for your ladder challenge — confirm it to update the ladder.',
      });
    });

    res.status(200).json({ message: 'Result reported — waiting for the other player to confirm.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Report ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong recording the result.' });
  }
});

// ---------- CONFIRM A REPORTED RESULT (moves ladder positions) ----------
router.post('/:id/confirm', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;

  try {
    await pool.withTransaction(async (client) => {
      const result = await client.query('SELECT * FROM ladder_challenges WHERE id = $1 FOR UPDATE', [challengeId]);
      if (result.rows.length === 0) {
        throw new RouteError(404, 'Challenge not found.');
      }
      const challenge = result.rows[0];

      if (challenge.challenger_id !== userId && challenge.defender_id !== userId) {
        throw new RouteError(403, 'Only the two players in this challenge can confirm it.');
      }
      if (challenge.status !== 'reported') {
        throw new RouteError(409, 'This challenge has no reported result to confirm.');
      }
      if (challenge.reported_by === userId) {
        throw new RouteError(400, 'You cannot confirm your own report.');
      }

      // Lock every row on this sport+city ladder for the duration — a
      // position swap shifts a whole range of rows, and this must never
      // interleave with another challenge's confirm resolving at the same
      // time on the same ladder.
      await client.query(
        'SELECT 1 FROM ladder_members WHERE sport = $1 AND city = $2 FOR UPDATE',
        [challenge.sport, challenge.city]
      );

      const challengerWon = challenge.winner_id === challenge.challenger_id;
      if (challengerWon) {
        const positionsResult = await client.query(
          'SELECT user_id, position FROM ladder_members WHERE sport = $1 AND city = $2 AND user_id = ANY($3::int[])',
          [challenge.sport, challenge.city, [challenge.challenger_id, challenge.defender_id]]
        );
        const challengerRow = positionsResult.rows.find((r) => r.user_id === challenge.challenger_id);
        const defenderRow = positionsResult.rows.find((r) => r.user_id === challenge.defender_id);

        // Either player could have left the ladder since the challenge was
        // sent — nothing to move in that case, the challenge still records
        // who won, it just no longer affects standings.
        if (challengerRow && defenderRow) {
          const oldChallengerPosition = challengerRow.position;
          const newPosition = defenderRow.position;

          // Everyone strictly between the two old positions shifts down one
          // (the standard ladder-climb) before the challenger takes the
          // defender's old spot.
          await client.query(
            `UPDATE ladder_members SET position = position + 1
             WHERE sport = $1 AND city = $2 AND position >= $3 AND position < $4`,
            [challenge.sport, challenge.city, newPosition, oldChallengerPosition]
          );
          await client.query(
            'UPDATE ladder_members SET position = $1 WHERE sport = $2 AND city = $3 AND user_id = $4',
            [newPosition, challenge.sport, challenge.city, challenge.challenger_id]
          );
        }
      }
      // Defender win: no position change.

      await client.query(
        `UPDATE ladder_challenges SET status = 'confirmed', updated_at = NOW() WHERE id = $1 AND status = 'reported'`,
        [challengeId]
      );

      await createNotifications(client, [challenge.challenger_id, challenge.defender_id].filter((id) => id !== userId), {
        type: 'ladder_confirmed',
        title: 'Ladder result confirmed',
        body: challengerWon
          ? 'The challenger won — ladder positions have been updated.'
          : 'The result was confirmed — no change in ladder positions.',
      });
    });

    res.status(200).json({ message: 'Result confirmed.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Confirm ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong confirming the result.' });
  }
});

// ---------- DISPUTE A REPORTED RESULT ----------
// No host to arbitrate a dispute on a standalone ladder (unlike a
// tournament match), so this just reverts to 'accepted' and lets either
// player report again, rather than needing a dispute-resolution flow.
router.post('/:id/reject-report', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;

  try {
    await pool.withTransaction(async (client) => {
      const result = await client.query('SELECT * FROM ladder_challenges WHERE id = $1 FOR UPDATE', [challengeId]);
      if (result.rows.length === 0) {
        throw new RouteError(404, 'Challenge not found.');
      }
      const challenge = result.rows[0];

      if (challenge.challenger_id !== userId && challenge.defender_id !== userId) {
        throw new RouteError(403, 'Only the two players in this challenge can dispute it.');
      }
      if (challenge.status !== 'reported') {
        throw new RouteError(409, 'This challenge has no reported result to dispute.');
      }
      if (challenge.reported_by === userId) {
        throw new RouteError(400, 'You cannot dispute your own report.');
      }

      await client.query(
        `UPDATE ladder_challenges
         SET status = 'accepted', player1_units = NULL, player2_units = NULL,
             set_scores = NULL, winner_id = NULL, reported_by = NULL, updated_at = NOW()
         WHERE id = $1 AND status = 'reported'`,
        [challengeId]
      );

      const reporterId = challenge.reported_by;
      await createNotification(client, {
        userId: reporterId,
        type: 'ladder_report',
        title: 'Ladder result disputed',
        body: 'The other player disputed your reported result — report it again once you agree on the score.',
      });
    });

    res.status(200).json({ message: 'Report disputed — ask to report again once you agree on the score.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Dispute ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong disputing the result.' });
  }
});

// ---------- CANCEL A PENDING CHALLENGE ----------
router.delete('/:id', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;

  try {
    const result = await pool.query('SELECT * FROM ladder_challenges WHERE id = $1', [challengeId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Challenge not found.' });
    }
    const challenge = result.rows[0];

    if (challenge.challenger_id !== userId) {
      return res.status(403).json({ error: 'Only the player who sent this challenge can cancel it.' });
    }
    if (challenge.status !== 'pending') {
      return res.status(409).json({ error: 'Only a still-pending challenge can be cancelled.' });
    }

    await pool.query(
      `UPDATE ladder_challenges SET status = 'cancelled', updated_at = NOW() WHERE id = $1`,
      [challengeId]
    );
    res.status(200).json({ message: 'Challenge cancelled.' });
  } catch (err) {
    console.error('Cancel ladder challenge error:', err);
    res.status(500).json({ error: 'Something went wrong cancelling the challenge.' });
  }
});

module.exports = router;
