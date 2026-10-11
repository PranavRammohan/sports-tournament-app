// blockRoutes.js
// Self-service blocking — see blocking.js for why this exists and
// migration_blocked_users.sql for the table. Blocking here only affects
// player discovery/friendly-match challenges (wired into friendlyRoutes.js
// and sportsRoutes.js); it never touches tournament membership or match
// visibility — see migration_blocked_users.sql's header for that scope
// boundary.
const express = require('express');
const router = express.Router();
const pool = require('./db');

// ---------- BLOCK A PLAYER ----------
router.post('/', async (req, res) => {
  const userId = req.userId;
  const blockedId = req.body.userId != null ? parseInt(req.body.userId, 10) : null;

  if (!blockedId) {
    return res.status(400).json({ error: 'A player to block is required.' });
  }
  if (blockedId === userId) {
    return res.status(400).json({ error: "You can't block yourself." });
  }

  try {
    const userResult = await pool.query('SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL', [blockedId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'Player not found.' });
    }

    await pool.query(
      `INSERT INTO blocked_users (blocker_id, blocked_id) VALUES ($1, $2)
       ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
      [userId, blockedId]
    );

    res.status(200).json({ message: 'Player blocked.' });
  } catch (err) {
    console.error('Block player error:', err);
    res.status(500).json({ error: 'Something went wrong blocking this player.' });
  }
});

// ---------- UNBLOCK A PLAYER ----------
router.delete('/:userId', async (req, res) => {
  const userId = req.userId;
  const blockedId = parseInt(req.params.userId, 10);

  try {
    await pool.query(
      'DELETE FROM blocked_users WHERE blocker_id = $1 AND blocked_id = $2',
      [userId, blockedId]
    );
    res.status(200).json({ message: 'Player unblocked.' });
  } catch (err) {
    console.error('Unblock player error:', err);
    res.status(500).json({ error: 'Something went wrong unblocking this player.' });
  }
});

// ---------- MY BLOCKED PLAYERS ----------
// Only players *I've* blocked — not the reverse. A user who blocked me
// shouldn't be surfaced to me as "someone I blocked" with an unblock button,
// since I never blocked them; they just disappear from my discovery results
// via blocking.js's symmetric exclusion.
router.get('/', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.location, u.city
       FROM blocked_users bu
       JOIN users u ON u.id = bu.blocked_id
       WHERE bu.blocker_id = $1
       ORDER BY bu.created_at DESC`,
      [userId]
    );
    res.status(200).json({ blocked: result.rows });
  } catch (err) {
    console.error('List blocked players error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your blocked players.' });
  }
});

module.exports = router;
