// leagueRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

router.post('/create', async (req, res) => {
  const userId = req.userId;
  const { sport, area, seasonStart, seasonEnd } = req.body;

  if (!sport || !area || !seasonStart || !seasonEnd) {
    return res.status(400).json({ error: 'All fields are required.' });
  }

  try {
    const result = await pool.query(
      `INSERT INTO leagues (sport, area, season_start, season_end, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, sport, area, season_start, season_end`,
      [sport, area, seasonStart, seasonEnd, userId]
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

router.get('/', async (req, res) => {
  const { sport, area } = req.query;

  try {
    let query = `
      SELECT l.id, l.sport, l.area, l.season_start, l.season_end,
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

    query += ` GROUP BY l.id ORDER BY l.season_start ASC`;

    const result = await pool.query(query, params);
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('Browse leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching leagues.' });
  }
});

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

router.get('/:id', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }

    const leaderboard = await pool.query(
      `SELECT u.id, u.username, us.rating, us.matches_played, us.wins, us.losses
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1
       WHERE lm.league_id = $2
       ORDER BY us.rating DESC`,
      [league.rows[0].sport, leagueId]
    );

    res.status(200).json({ league: league.rows[0], leaderboard: leaderboard.rows });
  } catch (err) {
    console.error('League detail error:', err);
    res.status(500).json({ error: 'Something went wrong fetching league details.' });
  }
});

module.exports = router;