// friendlyRoutes.js
// Friendly (unranked) matches — deliberately its own table and route file,
// not a nullable-league row bolted onto matches.js/matches. See
// migration_friendly_matches.sql's header for why: matches and its readers
// (history, head-to-head, rating-history, checkForRatingDrift,
// finalizeMatch) all assume a real league, and a friendly is required to
// never touch matches_played/wins/losses/rating at all. Keeping this fully
// separate means zero risk of a friendly leaking into any of those existing
// queries — this file never calls into ratingEngine.js or touches
// user_sports at all.
//
// Singles only for v1 — format is still a real column (not hardcoded),
// just always 'singles' for now; doubles friendly-matchmaking needs its own
// 4-player pairing flow, a natural v2.
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { createNotification } = require('./notifications');

// Same small validators matchRoutes.js has — kept as a local copy per this
// codebase's convention of duplicating small per-file helpers rather than
// sharing a module for a narrow check (see CLAUDE.md).
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

function winnerUnitsAreConsistent(winnerIsPlayer1, player1Units, player2Units) {
  return winnerIsPlayer1 ? player1Units > player2Units : player2Units > player1Units;
}

// ---------- FIND PLAYERS WITH A SIMILAR RATING ----------
router.get('/nearby', async (req, res) => {
  const userId = req.userId;
  const { sport, city, area } = req.query;

  if (!sport) {
    return res.status(400).json({ error: 'Sport is required.' });
  }

  try {
    const myRatingResult = await pool.query(
      'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
      [userId, sport, 'singles']
    );
    if (myRatingResult.rows.length === 0) {
      return res.status(400).json({ error: "Add this sport to your profile first — you need a rating to find similarly-rated players." });
    }
    const myRating = myRatingResult.rows[0].rating;

    // city/area are optional — letting a traveling player search a
    // different city than their own home city is the whole point of these
    // filters, so unlike Browse's default-to-your-own-city seeding, there's
    // no server-side default here; the mobile client seeds the initial
    // value and the user is free to change it.
    let query = `
      SELECT u.id, u.username, u.location, u.city, us.rating
      FROM users u
      JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = 'singles'
      WHERE u.id != $2 AND u.deleted_at IS NULL
    `;
    const params = [sport, userId];

    if (city) {
      params.push(city);
      query += ` AND u.city = $${params.length}`;
    }
    if (area) {
      params.push(area);
      query += ` AND u.location = $${params.length}`;
    }

    params.push(myRating);
    query += ` ORDER BY ABS(us.rating - $${params.length}) ASC LIMIT 20`;

    const result = await pool.query(query, params);

    res.status(200).json({ players: result.rows, myRating });
  } catch (err) {
    console.error('Nearby-rating search error:', err);
    res.status(500).json({ error: 'Something went wrong finding nearby players.' });
  }
});

// ---------- SEND A FRIENDLY CHALLENGE ----------
router.post('/challenge', async (req, res) => {
  const userId = req.userId;
  const { opponentId, sport, proposedTime, venue } = req.body;

  if (!opponentId || !sport) {
    return res.status(400).json({ error: 'Opponent and sport are required.' });
  }
  if (opponentId === userId) {
    return res.status(400).json({ error: "You can't challenge yourself." });
  }

  try {
    const sportsResult = await pool.query(
      `SELECT user_id FROM user_sports WHERE sport = $1 AND format = 'singles' AND user_id = ANY($2::int[])`,
      [sport, [userId, opponentId]]
    );
    const idsWithSport = new Set(sportsResult.rows.map((r) => r.user_id));
    if (!idsWithSport.has(userId) || !idsWithSport.has(opponentId)) {
      return res.status(400).json({ error: 'Both players need this sport on their profile first.' });
    }

    const result = await pool.query(
      `INSERT INTO friendly_matches (sport, format, player1_id, player2_id, status, proposed_time, venue)
       VALUES ($1, 'singles', $2, $3, 'pending', $4, $5)
       RETURNING *`,
      [sport, userId, opponentId, proposedTime || null, venue || null]
    );
    const challenge = result.rows[0];

    await createNotification(pool, {
      userId: opponentId,
      type: 'friendly_challenge',
      title: 'Friendly match challenge',
      body: `You've been challenged to a friendly ${sport.replace('_', ' ')} match.`,
    });

    res.status(201).json({ challenge });
  } catch (err) {
    console.error('Send friendly challenge error:', err);
    res.status(500).json({ error: 'Something went wrong sending the challenge.' });
  }
});

// ---------- MY PENDING / ACCEPTED FRIENDLY MATCHES ----------
router.get('/pending', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT fm.*, p1.username AS player1_username, p2.username AS player2_username
       FROM friendly_matches fm
       JOIN users p1 ON p1.id = fm.player1_id
       JOIN users p2 ON p2.id = fm.player2_id
       WHERE (fm.player1_id = $1 OR fm.player2_id = $1)
         AND fm.status IN ('pending', 'accepted')
       ORDER BY fm.created_at DESC`,
      [userId]
    );

    const incoming = result.rows.filter((r) => r.status === 'pending' && r.player2_id === userId);
    const outgoing = result.rows.filter((r) => r.status === 'pending' && r.player1_id === userId);
    const accepted = result.rows.filter((r) => r.status === 'accepted');

    res.status(200).json({ incoming, outgoing, accepted });
  } catch (err) {
    console.error('Get pending friendlies error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your friendly matches.' });
  }
});

// ---------- ACCEPT / DECLINE A CHALLENGE ----------
router.post('/:id/respond', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;
  const { accept } = req.body;

  try {
    const result = await pool.query('SELECT * FROM friendly_matches WHERE id = $1', [challengeId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Challenge not found.' });
    }
    const challenge = result.rows[0];

    if (challenge.player2_id !== userId) {
      return res.status(403).json({ error: 'Only the challenged player can respond to this.' });
    }
    if (challenge.status !== 'pending') {
      return res.status(400).json({ error: 'This challenge has already been responded to.' });
    }

    const newStatus = accept === true ? 'accepted' : 'declined';
    await pool.query(
      'UPDATE friendly_matches SET status = $1, updated_at = NOW() WHERE id = $2',
      [newStatus, challengeId]
    );

    await createNotification(pool, {
      userId: challenge.player1_id,
      type: 'friendly_response',
      title: accept === true ? 'Friendly challenge accepted' : 'Friendly challenge declined',
      body: accept === true
        ? 'Your friendly match challenge was accepted — coordinate a time to play!'
        : 'Your friendly match challenge was declined.',
    });

    res.status(200).json({ message: `Challenge ${newStatus}.` });
  } catch (err) {
    console.error('Respond to friendly challenge error:', err);
    res.status(500).json({ error: 'Something went wrong responding to the challenge.' });
  }
});

// ---------- REPORT A FRIENDLY MATCH RESULT ----------
// Unlike a real tournament match, whoever reports it is final immediately —
// no opponent confirmation step. There's nothing at stake (no rating, no
// points), so the confirm/reject dance real matches need doesn't earn its
// complexity here. Never touches ratingEngine.js or user_sports.
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
    const result = await pool.query('SELECT * FROM friendly_matches WHERE id = $1', [challengeId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Friendly match not found.' });
    }
    const match = result.rows[0];

    if (match.player1_id !== userId && match.player2_id !== userId) {
      return res.status(403).json({ error: 'Only the two players in this match can report a result.' });
    }
    if (match.status !== 'accepted') {
      return res.status(400).json({ error: 'This match needs to be accepted before a result can be reported.' });
    }
    if (winnerId !== match.player1_id && winnerId !== match.player2_id) {
      return res.status(400).json({ error: 'Winner must be one of the two players.' });
    }
    if (!winnerUnitsAreConsistent(winnerId === match.player1_id, player1Units, player2Units)) {
      return res.status(400).json({ error: "The declared winner's score must be higher than the opponent's." });
    }

    await pool.query(
      `UPDATE friendly_matches
       SET player1_units = $1, player2_units = $2, set_scores = $3, winner_id = $4,
           reported_by = $5, status = 'completed', updated_at = NOW()
       WHERE id = $6`,
      [player1Units, player2Units, JSON.stringify(setScores || []), winnerId, userId, challengeId]
    );

    res.status(200).json({ message: 'Result recorded.' });
  } catch (err) {
    console.error('Report friendly match error:', err);
    res.status(500).json({ error: 'Something went wrong recording the result.' });
  }
});

// ---------- CANCEL A PENDING CHALLENGE ----------
router.delete('/:id', async (req, res) => {
  const userId = req.userId;
  const challengeId = req.params.id;

  try {
    const result = await pool.query('SELECT * FROM friendly_matches WHERE id = $1', [challengeId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Challenge not found.' });
    }
    const challenge = result.rows[0];

    if (challenge.player1_id !== userId) {
      return res.status(403).json({ error: 'Only the player who sent this challenge can cancel it.' });
    }
    if (challenge.status !== 'pending') {
      return res.status(400).json({ error: 'Only a still-pending challenge can be cancelled.' });
    }

    await pool.query('DELETE FROM friendly_matches WHERE id = $1', [challengeId]);
    res.status(200).json({ message: 'Challenge cancelled.' });
  } catch (err) {
    console.error('Cancel friendly challenge error:', err);
    res.status(500).json({ error: 'Something went wrong cancelling the challenge.' });
  }
});

module.exports = router;
