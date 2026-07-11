// sportsRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

const STARTING_RATING = 1000;

// ---------- SELECT SPORTS ----------
router.post('/select', async (req, res) => {
  const userId = req.userId;
  const { sports } = req.body;

  if (!Array.isArray(sports) || sports.length === 0) {
    return res.status(400).json({ error: 'Select at least one sport.' });
  }

  try {
    const insertPromises = sports.map((sport) =>
      pool.query(
        `INSERT INTO user_sports (user_id, sport, rating)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, sport) DO NOTHING`,
        [userId, sport, STARTING_RATING]
      )
    );
    await Promise.all(insertPromises);

    const result = await pool.query(
      'SELECT sport, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1',
      [userId]
    );

    res.status(201).json({ sports: result.rows });
  } catch (err) {
    console.error('Select sports error:', err);
    res.status(500).json({ error: 'Something went wrong saving your sports.' });
  }
});

// ---------- GET MY SPORTS ----------
router.get('/mine', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      'SELECT sport, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1',
      [userId]
    );
    res.status(200).json({ sports: result.rows });
  } catch (err) {
    console.error('Get sports error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your sports.' });
  }
});

module.exports = router;