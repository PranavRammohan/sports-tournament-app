// sportsRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { escapeLikePattern } = require('./sql');

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

// ---------- SEARCH PLAYERS (GAP-04 — discovery outside a shared league) ----------
// Unlike leagueRoutes.js's /:id/search-players, this is NOT scoped to a league
// or host — any authenticated user can search any other user. This is safe:
// PlayerProfileScreen's own backend calls (GET /sports/user/:userId and
// GET /matches/head-to-head/:userId) already have no shared-league check, so a
// search endpoint doesn't open anything that wasn't already reachable by id.
router.get('/search', async (req, res) => {
  const { q, sport, format } = req.query;

  if (!q || q.trim().length < 2) {
    return res.status(400).json({ error: 'Enter at least 2 characters to search.' });
  }

  try {
    const likePattern = `%${escapeLikePattern(q.trim())}%`;
    // Only join user_sports (and so only surface a rating) when both sport
    // and format are given — a bare LEFT JOIN with optional filters would
    // return one row per sport/format a user has, and DISTINCT can't collapse
    // those since the rating differs per row.
    const result =
      sport && format
        ? await pool.query(
            `SELECT DISTINCT u.id, u.username, u.location, us.rating
             FROM users u
             LEFT JOIN user_sports us ON us.user_id = u.id AND us.sport = $2 AND us.format = $3
             WHERE u.username ILIKE $1
             ORDER BY u.username
             LIMIT 20`,
            [likePattern, sport, format]
          )
        : await pool.query(
            `SELECT u.id, u.username, u.location, NULL AS rating
             FROM users u
             WHERE u.username ILIKE $1
             ORDER BY u.username
             LIMIT 20`,
            [likePattern]
          );
    res.status(200).json({ users: result.rows });
  } catch (err) {
    console.error('Search players error:', err);
    res.status(500).json({ error: 'Something went wrong searching for players.' });
  }
});

// Seeds both the singles and doubles user_sports rows for one sport at the
// given skill level (table tennis shares one rating across both formats by
// design, but still gets both rows — see CLAUDE.md). `client` is whatever the
// caller has in scope (plain `pool`, or a transaction client) — same
// zero-branching convention as notifications.js/scheduling.js. Returns an
// error message string on bad input, or null on success, rather than
// throwing, so both this file's own /select route and leagueRoutes.js's
// guest-add flow (POST /:id/add-guest — a guest needs the same starting-
// rating seeding a real signup gets) can each decide their own status code.
async function seedStartingRating(client, userId, sport, level) {
  const sportRatings = STARTING_RATINGS[sport];
  if (!sportRatings) {
    return `Unknown sport: ${sport}`;
  }
  const rating = sportRatings[level];
  if (rating == null) {
    return `Unknown skill level "${level}" for ${sport}`;
  }

  await client.query(
    `INSERT INTO user_sports (user_id, sport, format, rating)
     VALUES ($1, $2, 'singles', $3)
     ON CONFLICT (user_id, sport, format) DO NOTHING`,
    [userId, sport, rating]
  );
  await client.query(
    `INSERT INTO user_sports (user_id, sport, format, rating)
     VALUES ($1, $2, 'doubles', $3)
     ON CONFLICT (user_id, sport, format) DO NOTHING`,
    [userId, sport, rating]
  );
  return null;
}

// ---------- SELECT SPORTS (signup, or adding a sport later) ----------
router.post('/select', async (req, res) => {
  const userId = req.userId;
  const { sports } = req.body;

  if (!sports || !Array.isArray(sports) || sports.length === 0) {
    return res.status(400).json({ error: 'Please select at least one sport.' });
  }

  try {
    for (const s of sports) {
      const error = await seedStartingRating(pool, userId, s.sport, s.level);
      if (error) {
        return res.status(400).json({ error });
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

// ---------- GET ANOTHER PLAYER'S PUBLIC PROFILE (#8) ----------
// Deliberately excludes phone number — this is reachable by tapping any
// player's name (e.g. on a league leaderboard), a much more casual action
// than being paired against them in a scheduled match, where phone number
// is already shared for coordination purposes.
router.get('/user/:userId', async (req, res) => {
  const targetUserId = req.params.userId;

  try {
    const userResult = await pool.query(
      'SELECT id, username, location, gender, profile_pic_url, created_at FROM users WHERE id = $1',
      [targetUserId]
    );
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'Player not found.' });
    }

    const sportsResult = await pool.query(
      'SELECT sport, format, rating, matches_played, wins, losses FROM user_sports WHERE user_id = $1',
      [targetUserId]
    );

    res.status(200).json({ user: userResult.rows[0], sports: sportsResult.rows });
  } catch (err) {
    console.error('Get player profile error:', err);
    res.status(500).json({ error: "Something went wrong fetching this player's profile." });
  }
});

// Reconstructs a rating-over-time series from the current rating snapshot
// and a chronologically-ordered (oldest first) list of {my_rating_change}
// rows. There's no materialized rating-history table — only the current
// snapshot on user_sports.rating, plus a per-match delta on matches/
// playoff_matches — so the baseline is computed by subtracting every
// recorded delta from the current rating (baseline + sum(deltas) = current,
// by construction, regardless of what the original starting rating was or
// whether it's ever been manually corrected), then walking forward
// re-applying each delta in order. Exported for unit testing (pure
// function, no DB access) — the route below just wires real data into it.
function reconstructRatingHistory(currentRating, matchRows) {
  const deltas = matchRows.map((r) => parseFloat(r.my_rating_change) || 0);
  const totalDelta = deltas.reduce((sum, d) => sum + d, 0);
  let running = currentRating - totalDelta;

  const history = [{ date: null, rating: Math.round(running * 10) / 10 }];
  matchRows.forEach((r, i) => {
    running += deltas[i];
    history.push({
      date: r.created_at,
      rating: Math.round(running * 10) / 10,
    });
  });
  return history;
}

// ---------- RATING HISTORY (for a rating trend chart) ----------
router.get('/user/:userId/rating-history', async (req, res) => {
  const targetUserId = req.params.userId;
  const { sport, format } = req.query;

  if (!sport || !format) {
    return res.status(400).json({ error: 'Please specify a sport and format.' });
  }

  try {
    const currentResult = await pool.query(
      'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
      [targetUserId, sport, format]
    );
    if (currentResult.rows.length === 0) {
      return res.status(404).json({ error: 'This player has not played this sport/format.' });
    }
    const currentRating = parseFloat(currentResult.rows[0].rating);

    // Table tennis shares one rating across singles/doubles — a doubles
    // match affects the same rating a singles match does, so don't filter
    // by format for that sport (same convention as matchRoutes.js's
    // checkForRatingDrift).
    const formatFilter = sport === 'table_tennis' ? null : format;

    const matchesResult = await pool.query(
      `SELECT * FROM (
         SELECT m.id, m.created_at,
                CASE
                  WHEN m.player1_id = $1 THEN m.player1_rating_change
                  WHEN m.player2_id = $1 THEN m.player2_rating_change
                  WHEN m.player1_partner_id = $1 THEN m.player1_partner_rating_change
                  WHEN m.player2_partner_id = $1 THEN m.player2_partner_rating_change
                END AS my_rating_change
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         WHERE m.status = 'confirmed' AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
           AND (m.player1_id = $1 OR m.player2_id = $1 OR m.player1_partner_id = $1 OR m.player2_partner_id = $1)
         UNION ALL
         SELECT pm.id, pm.created_at,
                CASE
                  WHEN pm.player1_id = $1 THEN pm.player1_rating_change
                  WHEN pm.player2_id = $1 THEN pm.player2_rating_change
                  WHEN pm.player1_partner_id = $1 THEN pm.player1_partner_rating_change
                  WHEN pm.player2_partner_id = $1 THEN pm.player2_partner_rating_change
                END AS my_rating_change
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         WHERE pm.status = 'confirmed' AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
           AND (pm.player1_id = $1 OR pm.player2_id = $1 OR pm.player1_partner_id = $1 OR pm.player2_partner_id = $1)
       ) combined
       ORDER BY created_at ASC`,
      [targetUserId, sport, formatFilter]
    );

    const history = reconstructRatingHistory(currentRating, matchesResult.rows);

    res.status(200).json({ history });
  } catch (err) {
    console.error('Rating history error:', err);
    res.status(500).json({ error: "Something went wrong fetching this player's rating history." });
  }
});

// Attached the same way matchRoutes.js/playoffRoutes.js/leagueRoutes.js
// attach their own module-private helpers, and db.js attaches
// withTransaction/RouteError — lets the test suite reach this pure function
// without changing how server.js consumes this file.
router.reconstructRatingHistory = reconstructRatingHistory;
router.seedStartingRating = seedStartingRating;

module.exports = router;