// sportsRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

// Starting ratings per sport per skill level, matching each sport's real
// practical rating range as used in this app.
const STARTING_RATINGS = {
  badminton: {
    beginner: 6000,
    intermediate: 6500,
    'higher intermediate': 7000,
    advanced: 7500,
    pro: 8500,
  },
  tennis: {
    beginner: 2.5,
    'lower intermediate': 4.5,
    intermediate: 6.5,
    'intermediate advanced': 8.5,
    advanced: 10.5,
    pro: 13,
  },
  table_tennis: {
    beginner: 1000,
    'early intermediate': 1400,
    intermediate: 1600,
    'higher intermediate': 1800,
    advanced: 2200,
    pro: 2500,
  },
  pickleball: {
    beginner: 2.5,
    intermediate: 3.5,
    'mid-intermediate': 4,
    advanced: 5,
    pro: 7,
  },
};

// ---------- SELECT SPORTS (signup, or adding a sport later) ----------
router.post('/select', async (req, res) => {
  const userId = req.userId;
  const { sports } = req.body;

  if (!sports || !Array.isArray(sports) || sports.length === 0) {
    return res.status(400).json({ error: 'Please select at least one sport.' });
  }

  try {
    for (const s of sports) {
      const sportRatings = STARTING_RATINGS[s.sport];
      if (!sportRatings) {
        return res.status(400).json({ error: `Unknown sport: ${s.sport}` });
      }
      const rating = sportRatings[s.level];
      if (rating == null) {
        return res.status(400).json({ error: `Unknown skill level "${s.level}" for ${s.sport}` });
      }

      if (s.sport === 'table_tennis') {
        // Table tennis shares one rating across singles/doubles.
        await pool.query(
          `INSERT INTO user_sports (user_id, sport, format, rating)
           VALUES ($1, $2, 'singles', $3)
           ON CONFLICT (user_id, sport, format) DO NOTHING`,
          [userId, s.sport, rating]
        );
        await pool.query(
          `INSERT INTO user_sports (user_id, sport, format, rating)
           VALUES ($1, $2, 'doubles', $3)
           ON CONFLICT (user_id, sport, format) DO NOTHING`,
          [userId, s.sport, rating]
        );
      } else {
        await pool.query(
          `INSERT INTO user_sports (user_id, sport, format, rating)
           VALUES ($1, $2, 'singles', $3)
           ON CONFLICT (user_id, sport, format) DO NOTHING`,
          [userId, s.sport, rating]
        );
        await pool.query(
          `INSERT INTO user_sports (user_id, sport, format, rating)
           VALUES ($1, $2, 'doubles', $3)
           ON CONFLICT (user_id, sport, format) DO NOTHING`,
          [userId, s.sport, rating]
        );
      }
    }

    res.status(201).json({ message: 'Sports selected successfully.' });
  } catch (err) {
    console.error('Select sports error:', err);
    res.status(500).json({ error: 'Something went wrong selecting your sports.' });
  }
});

// ---------- GET MY SPORTS ----------
router.get('/mine', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      'SELECT sport, format, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1',
      [userId]
    );
    res.status(200).json({ sports: result.rows });
  } catch (err) {
    console.error('Get my sports error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your sports.' });
  }
});

module.exports = router;