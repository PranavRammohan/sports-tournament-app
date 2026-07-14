// sportsRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

// Starting ratings per sport, per skill level — matches each sport's real-world scale
const STARTING_RATINGS = {
  tennis: { beginner: 2.5, intermediate: 5.0, advanced: 8.5, expert: 12.0 },
  badminton: { beginner: 1500, intermediate: 3000, advanced: 5000, expert: 7000 },
  table_tennis: { beginner: 800, intermediate: 1200, advanced: 1600, expert: 2000 },
  pickleball: { beginner: 2.5, intermediate: 3.5, advanced: 5.0, expert: 6.5 },
};

function getStartingRating(sport, level) {
  const scale = STARTING_RATINGS[sport] || STARTING_RATINGS.tennis;
  return scale[level] ?? scale.intermediate;
}

// ---------- SELECT SPORTS ----------
// Body: { sports: [{ sport: "tennis", level: "intermediate" }, ...] }
// Creates BOTH a singles and doubles rating row per sport, starting at the same value —
// they'll diverge over time as singles/doubles matches are played independently
// (except table tennis, which keeps them in sync since it uses one shared rating).
router.post('/select', async (req, res) => {
  const userId = req.userId;
  const { sports } = req.body;

  if (!Array.isArray(sports) || sports.length === 0) {
    return res.status(400).json({ error: 'Select at least one sport.' });
  }

  const validLevels = ['beginner', 'intermediate', 'advanced', 'expert'];
  for (const entry of sports) {
    if (!entry.sport || !validLevels.includes(entry.level)) {
      return res.status(400).json({ error: 'Each sport needs a valid skill level.' });
    }
  }

  try {
    const insertPromises = [];
    for (const entry of sports) {
      const startingRating = getStartingRating(entry.sport, entry.level);
      for (const format of ['singles', 'doubles']) {
        insertPromises.push(
          pool.query(
            `INSERT INTO user_sports (user_id, sport, format, rating)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, sport, format) DO NOTHING`,
            [userId, entry.sport, format, startingRating]
          )
        );
      }
    }
    await Promise.all(insertPromises);

    const result = await pool.query(
      'SELECT sport, format, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1',
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
      'SELECT sport, format, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1 ORDER BY sport, format',
      [userId]
    );
    res.status(200).json({ sports: result.rows });
  } catch (err) {
    console.error('Get sports error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your sports.' });
  }
});

module.exports = router;