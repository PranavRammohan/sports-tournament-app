// notificationRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

// ---------- LIST MY NOTIFICATIONS ----------
router.get('/', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT id, type, title, body, league_id, read, created_at
       FROM notifications
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [userId]
    );
    res.status(200).json({ notifications: result.rows });
  } catch (err) {
    console.error('Get notifications error:', err);
    res.status(500).json({ error: 'Something went wrong fetching notifications.' });
  }
});

// ---------- UNREAD COUNT (for the badge) ----------
router.get('/unread-count', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND read = false`,
      [userId]
    );
    res.status(200).json({ count: parseInt(result.rows[0].count, 10) });
  } catch (err) {
    console.error('Get unread notification count error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your notification count.' });
  }
});

// ---------- MARK ONE AS READ ----------
router.patch('/:id/read', async (req, res) => {
  const userId = req.userId;
  const notificationId = req.params.id;

  try {
    const result = await pool.query(
      `UPDATE notifications SET read = true WHERE id = $1 AND user_id = $2 RETURNING id`,
      [notificationId, userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Notification not found.' });
    }
    res.status(200).json({ message: 'Marked as read.' });
  } catch (err) {
    console.error('Mark notification read error:', err);
    res.status(500).json({ error: 'Something went wrong updating that notification.' });
  }
});

// ---------- MARK ALL AS READ ----------
router.patch('/read-all', async (req, res) => {
  const userId = req.userId;

  try {
    await pool.query(
      `UPDATE notifications SET read = true WHERE user_id = $1 AND read = false`,
      [userId]
    );
    res.status(200).json({ message: 'All notifications marked as read.' });
  } catch (err) {
    console.error('Mark all notifications read error:', err);
    res.status(500).json({ error: 'Something went wrong updating your notifications.' });
  }
});

// ---------- REGISTER/REFRESH DEVICE PUSH TOKEN ----------
router.post('/device-token', async (req, res) => {
  const userId = req.userId;
  const { token } = req.body;

  if (!token || typeof token !== 'string') {
    return res.status(400).json({ error: 'A device token is required.' });
  }

  // #debug — temporary, see the matching comment on /device-token/status below.
  console.log(`[debug] device-token register: userId=${userId} length=${token.length} value="${token}"`);

  try {
    await pool.query('UPDATE users SET fcm_token = $1 WHERE id = $2', [token, userId]);
    res.status(200).json({ message: 'Device token registered.' });
  } catch (err) {
    console.error('Register device token error:', err);
    res.status(500).json({ error: 'Something went wrong registering your device.' });
  }
});

// ---------- TEMP DIAGNOSTIC: is a device token on file? (#debug) ----------
// Only exists to debug the initial push-notification rollout without
// needing direct DB/log access — reveals nothing beyond a boolean and the
// token's last 6 characters. Remove once push is confirmed working.
router.get('/device-token/status', async (req, res) => {
  const userId = req.userId;
  try {
    const result = await pool.query('SELECT fcm_token FROM users WHERE id = $1', [userId]);
    const token = result.rows[0]?.fcm_token;
    res.status(200).json({
      hasToken: !!token,
      tokenSuffix: token ? token.slice(-6) : null,
    });
  } catch (err) {
    console.error('Device token status error:', err);
    res.status(500).json({ error: 'Something went wrong checking device token status.' });
  }
});

module.exports = router;
