// leagueRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

// ---------- CREATE LEAGUE ----------
router.post('/create', async (req, res) => {
  const userId = req.userId;
  const { sport, area, seasonStart, seasonEnd, format, genderCategory } = req.body;

  if (!sport || !area || !seasonStart || !seasonEnd || !format || !genderCategory) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (!['singles', 'doubles'].includes(format)) {
    return res.status(400).json({ error: 'Format must be singles or doubles.' });
  }
  if (!['mens', 'womens'].includes(genderCategory)) {
    return res.status(400).json({ error: 'Gender category must be mens or womens.' });
  }

  try {
    const result = await pool.query(
      `INSERT INTO leagues (sport, area, season_start, season_end, created_by, format, gender_category)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, sport, area, season_start, season_end, format, gender_category`,
      [sport, area, seasonStart, seasonEnd, userId, format, genderCategory]
    );

    const league = result.rows[0];

    await pool.query(
      `INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)`,
      [league.id, userId]
    );

    res.status(201).json({ league });
  } catch (err) {
    console.error('Create league error:', err);
    res.status(500).json({ error: 'Something went wrong creating the league.' });
  }
});

// ---------- BROWSE LEAGUES ----------
router.get('/', async (req, res) => {
  const { sport, area, format, genderCategory } = req.query;

  try {
    let query = `
      SELECT l.id, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
             COUNT(lm.id) AS member_count
      FROM leagues l
      LEFT JOIN league_members lm ON lm.league_id = l.id
      WHERE 1=1
    `;
    const params = [];

    if (sport) {
      params.push(sport);
      query += ` AND l.sport = $${params.length}`;
    }
    if (area) {
      params.push(area);
      query += ` AND l.area = $${params.length}`;
    }
    if (format) {
      params.push(format);
      query += ` AND l.format = $${params.length}`;
    }
    if (genderCategory) {
      params.push(genderCategory);
      query += ` AND l.gender_category = $${params.length}`;
    }

    query += ` GROUP BY l.id ORDER BY l.season_start ASC`;

    const result = await pool.query(query, params);
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('Browse leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching leagues.' });
  }
});

// ---------- MY LEAGUES ----------
router.get('/mine', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT l.id, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
              COUNT(lm2.id) AS member_count
       FROM league_members lm
       JOIN leagues l ON l.id = lm.league_id
       LEFT JOIN league_members lm2 ON lm2.league_id = l.id
       WHERE lm.user_id = $1
       GROUP BY l.id
       ORDER BY l.season_start ASC`,
      [userId]
    );
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('My leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your leagues.' });
  }
});

// ---------- JOIN LEAGUE ----------
router.post('/:id/join', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }

    const existing = await pool.query(
      'SELECT id FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'You already joined this league.' });
    }

    await pool.query(
      'INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)',
      [leagueId, userId]
    );

    res.status(201).json({ message: 'Joined league successfully.' });
  } catch (err) {
    console.error('Join league error:', err);
    res.status(500).json({ error: 'Something went wrong joining the league.' });
  }
});

// ---------- LEAGUE DETAIL + LEADERBOARD ----------
router.get('/:id', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }

    const leagueData = league.rows[0];

    const leaderboard = await pool.query(
      `SELECT u.id, u.username, u.gender, us.rating, us.matches_played, us.wins, us.losses
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY us.rating DESC`,
      [leagueData.sport, leagueData.format, leagueId]
    );

    res.status(200).json({ league: leagueData, leaderboard: leaderboard.rows });
  } catch (err) {
    console.error('League detail error:', err);
    res.status(500).json({ error: 'Something went wrong fetching league details.' });
  }
});

// ---------- MATCH HISTORY FOR A LEAGUE ----------
router.get('/:id/matches', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const result = await pool.query(
      `SELECT m.id, m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
              m.player1_units, m.player2_units, m.set_scores, m.winner_id,
              m.status, m.created_at,
              p1.username as player1_username, p2.username as player2_username,
              pp1.username as player1_partner_username, pp2.username as player2_partner_username
       FROM matches m
       JOIN users p1 ON p1.id = m.player1_id
       JOIN users p2 ON p2.id = m.player2_id
       LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
       WHERE m.league_id = $1 AND m.status = 'confirmed'
       ORDER BY m.created_at DESC`,
      [leagueId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Match history error:', err);
    res.status(500).json({ error: 'Something went wrong fetching match history.' });
  }
});

module.exports = router;