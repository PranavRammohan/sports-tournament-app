// playoffRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

// Generates standard tournament bracket seed order for any power-of-two size,
// e.g. size=8 -> [1,8,4,5,2,7,3,6] (grouped in pairs: 1v8, 4v5, 2v7, 3v6),
// ensuring top seeds can't meet until later rounds.
function generateSeedOrder(size) {
  let result = [1, 2];
  while (result.length < size) {
    const newSize = result.length * 2;
    const newResult = [];
    for (const seed of result) {
      newResult.push(seed);
      newResult.push(newSize + 1 - seed);
    }
    result = newResult;
  }
  return result;
}

function isPowerOfTwo(n) {
  return n > 0 && (n & (n - 1)) === 0;
}

// ---------- GENERATE PLAYOFF BRACKET (host only, once, singles only) ----------
router.post('/:leagueId/generate', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.leagueId;
  const { qualifierCount } = req.body;

  if (!isPowerOfTwo(qualifierCount) || qualifierCount < 2) {
    return res.status(400).json({ error: 'Qualifier count must be a power of 2 (2, 4, 8, 16...).' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can start playoffs.' });
    }
    if (league.format !== 'singles') {
      return res.status(400).json({ error: 'Brackets are currently only supported for singles leagues.' });
    }

    const existing = await pool.query('SELECT id FROM playoff_matches WHERE league_id = $1 LIMIT 1', [leagueId]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'A bracket has already been started for this league.' });
    }

    const standingsResult = await pool.query(
      `SELECT u.id, us.rating
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY us.rating DESC
       LIMIT $4`,
      [league.sport, league.format, leagueId, qualifierCount]
    );
    const qualifiers = standingsResult.rows;

    if (qualifiers.length < qualifierCount) {
      return res.status(400).json({ error: `Need at least ${qualifierCount} players in the leaderboard to start this bracket size.` });
    }

    const seedOrder = generateSeedOrder(qualifierCount);
    const totalRounds = Math.log2(qualifierCount);

    // Group seedOrder into round-1 pairs: [s1,s2, s3,s4, ...] -> (s1 vs s2), (s3 vs s4), ...
    for (let i = 0; i < seedOrder.length; i += 2) {
      const seedA = seedOrder[i];
      const seedB = seedOrder[i + 1];
      await pool.query(
        `INSERT INTO playoff_matches (league_id, round_number, position, player1_id, player2_id, status)
         VALUES ($1, 1, $2, $3, $4, 'ready')`,
        [leagueId, i / 2 + 1, qualifiers[seedA - 1].id, qualifiers[seedB - 1].id]
      );
    }

    for (let round = 2; round <= totalRounds; round++) {
      const matchesInRound = qualifierCount / Math.pow(2, round);
      for (let pos = 1; pos <= matchesInRound; pos++) {
        await pool.query(
          `INSERT INTO playoff_matches (league_id, round_number, position, status)
           VALUES ($1, $2, $3, 'pending')`,
          [leagueId, round, pos]
        );
      }
    }

    res.status(201).json({ message: 'Bracket generated.' });
  } catch (err) {
    console.error('Generate playoffs error:', err);
    res.status(500).json({ error: 'Something went wrong generating the bracket.' });
  }
});

// ---------- GET BRACKET ----------
router.get('/:leagueId', async (req, res) => {
  const leagueId = req.params.leagueId;

  try {
    const result = await pool.query(
      `SELECT pm.*, p1.username as player1_username, p2.username as player2_username
       FROM playoff_matches pm
       LEFT JOIN users p1 ON p1.id = pm.player1_id
       LEFT JOIN users p2 ON p2.id = pm.player2_id
       WHERE pm.league_id = $1
       ORDER BY pm.round_number ASC, pm.position ASC`,
      [leagueId]
    );
    res.status(200).json({ bracket: result.rows });
  } catch (err) {
    console.error('Get bracket error:', err);
    res.status(500).json({ error: 'Something went wrong fetching the bracket.' });
  }
});

async function advanceWinner(match) {
  const nextRound = match.round_number + 1;
  const nextPosition = Math.ceil(match.position / 2);
  const isUpperSlot = match.position % 2 === 1;

  const nextMatchResult = await pool.query(
    'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3',
    [match.league_id, nextRound, nextPosition]
  );

  if (nextMatchResult.rows.length > 0) {
    const nextMatch = nextMatchResult.rows[0];
    if (isUpperSlot) {
      await pool.query('UPDATE playoff_matches SET player1_id = $1 WHERE id = $2', [match.winner_id, nextMatch.id]);
    } else {
      await pool.query('UPDATE playoff_matches SET player2_id = $1 WHERE id = $2', [match.winner_id, nextMatch.id]);
    }

    const updatedNextMatch = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [nextMatch.id]);
    const um = updatedNextMatch.rows[0];
    if (um.player1_id && um.player2_id) {
      await pool.query(`UPDATE playoff_matches SET status = 'ready' WHERE id = $1`, [nextMatch.id]);
    }
  }
}

// ---------- REPORT A PLAYOFF MATCH RESULT (self, needs opponent confirmation) ----------
router.post('/match/:matchId/report', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { myUnits, opponentUnits, iWon, setScores } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];
    if (league.host_enters_scores) {
      return res.status(403).json({ error: 'This league requires the host to enter all scores.' });
    }

    if (match.status !== 'ready') {
      return res.status(409).json({ error: 'This match is not ready to be reported.' });
    }
    if (![match.player1_id, match.player2_id].includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }

    const winnerId = iWon ? userId : (userId === match.player1_id ? match.player2_id : match.player1_id);
    const player1Units = userId === match.player1_id ? myUnits : opponentUnits;
    const player2Units = userId === match.player1_id ? opponentUnits : myUnits;

    await pool.query(
      `UPDATE playoff_matches SET status = 'reported', reported_by = $1,
        player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5
       WHERE id = $6`,
      [userId, player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
    );

    res.status(200).json({ message: 'Result reported, waiting for confirmation.' });
  } catch (err) {
    console.error('Report playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong reporting the result.' });
  }
});

// ---------- HOST ENTERS A PLAYOFF MATCH RESULT DIRECTLY (auto-confirmed) ----------
router.post('/match/:matchId/report-as-host', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { player1Units, player2Units, player1Won, setScores } = req.body;

  if (player1Units == null || player2Units == null || player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    if (!league.host_enters_scores || league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the host can enter scores directly for this league.' });
    }

    if (match.status !== 'ready') {
      return res.status(409).json({ error: 'This match is not ready to be reported.' });
    }
    if (!match.player1_id || !match.player2_id) {
      return res.status(400).json({ error: 'Both players for this match are not yet determined.' });
    }

    const winnerId = player1Won ? match.player1_id : match.player2_id;

    await pool.query(
      `UPDATE playoff_matches SET status = 'confirmed', reported_by = $1,
        player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5
       WHERE id = $6`,
      [userId, player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
    );

    const updatedMatch = { ...match, winner_id: winnerId };
    await advanceWinner(updatedMatch);

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
    console.error('Host report playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong entering the score.' });
  }
});

// ---------- CONFIRM A PLAYOFF MATCH RESULT ----------
router.post('/match/:matchId/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'reported') {
      return res.status(409).json({ error: 'This match has no pending report to confirm.' });
    }
    if (![match.player1_id, match.player2_id].includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot confirm your own report.' });
    }

    await pool.query(`UPDATE playoff_matches SET status = 'confirmed' WHERE id = $1`, [matchId]);

    await advanceWinner(match);

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
    console.error('Confirm playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong confirming the match.' });
  }
});

// ---------- REJECT A PLAYOFF MATCH RESULT ----------
router.post('/match/:matchId/reject', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'reported') {
      return res.status(409).json({ error: 'This match has no pending report to reject.' });
    }
    if (![match.player1_id, match.player2_id].includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot reject your own report.' });
    }

    await pool.query(
      `UPDATE playoff_matches SET status = 'ready', reported_by = NULL, winner_id = NULL,
        player1_units = NULL, player2_units = NULL, set_scores = NULL
       WHERE id = $1`,
      [matchId]
    );

    res.status(200).json({ message: 'Result rejected. It can be reported again.' });
  } catch (err) {
    console.error('Reject playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong rejecting the match.' });
  }
});

module.exports = router;