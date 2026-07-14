// matchRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { calculateNewRatings } = require('./ratingEngine');

async function getRating(userId, sport, format) {
  const result = await pool.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, sport, format]
  );
  if (result.rows.length === 0) return null;
  return parseFloat(result.rows[0].rating);
}

// Keeps table_tennis singles+doubles rating in sync since it's one shared number
async function updateRating(userId, sport, format, newRating, won) {
  if (sport === 'table_tennis') {
    await pool.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport]
    );
  } else {
    await pool.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5 AND format = $6`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport, format]
    );
  }
}

// ---------- REPORT A MATCH ----------
router.post('/report', async (req, res) => {
  const userId = req.userId;
  const {
    leagueId,
    opponentId,
    partnerId,
    opponentPartnerId,
    myUnits,
    opponentUnits,
    iWon,
    setScores,
  } = req.body;

  if (!leagueId || !opponentId || myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.format === 'doubles' && (!partnerId || !opponentPartnerId)) {
      return res.status(400).json({ error: 'Doubles matches need a partner and opponent partner.' });
    }
    if (league.format === 'singles' && (partnerId || opponentPartnerId)) {
      return res.status(400).json({ error: 'Singles matches should not have partners.' });
    }

    const winnerId = iWon ? userId : opponentId;

    const result = await pool.query(
      `INSERT INTO matches
        (league_id, player1_id, player1_partner_id, player2_id, player2_partner_id,
         player1_units, player2_units, winner_id, reported_by, status, format, set_scores)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending', $10, $11)
       RETURNING *`,
      [
        leagueId,
        userId,
        partnerId || null,
        opponentId,
        opponentPartnerId || null,
        myUnits,
        opponentUnits,
        winnerId,
        userId,
        league.format,
        JSON.stringify(setScores || []),
      ]
    );

    res.status(201).json({ match: result.rows[0] });
  } catch (err) {
    console.error('Report match error:', err);
    res.status(500).json({ error: 'Something went wrong reporting the match.' });
  }
});

// ---------- GET MATCHES AWAITING MY CONFIRMATION ----------
router.get('/pending', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT m.*, l.sport, l.format as league_format,
              p1.username as player1_username, p2.username as player2_username,
              pp1.username as player1_partner_username, pp2.username as player2_partner_username
       FROM matches m
       JOIN leagues l ON l.id = m.league_id
       JOIN users p1 ON p1.id = m.player1_id
       JOIN users p2 ON p2.id = m.player2_id
       LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
       WHERE m.status = 'pending'
         AND m.reported_by != $1
         AND (m.player2_id = $1 OR m.player2_partner_id = $1 OR m.player1_id = $1 OR m.player1_partner_id = $1)
       ORDER BY m.created_at DESC`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Get pending matches error:', err);
    res.status(500).json({ error: 'Something went wrong fetching pending matches.' });
  }
});

// ---------- CONFIRM A MATCH ----------
router.post('/:id/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;

  try {
    const matchResult = await pool.query('SELECT * FROM matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'pending') {
      return res.status(409).json({ error: 'This match has already been processed.' });
    }

    const participants = [match.player1_id, match.player1_partner_id, match.player2_id, match.player2_partner_id];
    if (!participants.includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot confirm your own report.' });
    }

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];
    const { sport, format } = league;

    const rating1a = await getRating(match.player1_id, sport, format);
    const rating2a = await getRating(match.player2_id, sport, format);
    const rating1b = match.player1_partner_id ? await getRating(match.player1_partner_id, sport, format) : null;
    const rating2b = match.player2_partner_id ? await getRating(match.player2_partner_id, sport, format) : null;

    const team1Rating = rating1b != null ? (rating1a + rating1b) / 2 : rating1a;
    const team2Rating = rating2b != null ? (rating2a + rating2b) / 2 : rating2a;

    const team1Won = match.winner_id === match.player1_id;

    const { newRating1, newRating2 } = calculateNewRatings(
      sport, team1Rating, team2Rating, team1Won, match.player1_units, match.player2_units
    );

    const change1 = newRating1 - team1Rating;
    const change2 = newRating2 - team2Rating;

    const applyChange = async (playerId, individualRating, change, won) => {
      if (individualRating == null) return;
      const updated = Math.round((individualRating + change) * 10) / 10;
      await updateRating(playerId, sport, format, updated, won);
    };

    await applyChange(match.player1_id, rating1a, change1, team1Won);
    await applyChange(match.player2_id, rating2a, change2, !team1Won);
    await applyChange(match.player1_partner_id, rating1b, change1, team1Won);
    await applyChange(match.player2_partner_id, rating2b, change2, !team1Won);

    await pool.query(`UPDATE matches SET status = 'confirmed' WHERE id = $1`, [matchId]);

    res.status(200).json({ message: 'Match confirmed and ratings updated.' });
  } catch (err) {
    console.error('Confirm match error:', err);
    res.status(500).json({ error: 'Something went wrong confirming the match.' });
  }
});

module.exports = router;