// notifications.js
// A plain (non-router) module for writing in-app notification rows, used by
// matchRoutes.js, playoffRoutes.js, and leagueRoutes.js. This is a
// deliberate exception to the "route files duplicate small helpers instead
// of sharing a module" convention noted elsewhere in this codebase — that
// convention is about two files each re-implementing the same narrow check
// independently, not about a genuinely new cross-cutting capability. This
// follows the existing precedent of ratingEngine.js: a small module
// isolated from the route layer that multiple route files import.
//
// `client` is whatever the call site already has in scope — a
// transaction's `client` inside pool.withTransaction, or plain `pool` in
// routes that aren't transactional. pg.Pool and a transaction client share
// the same .query() interface, so this works either way with no branching.

const { sendPushNotification } = require('./push');

async function createNotification(client, { userId, type, title, body, leagueId = null }) {
  if (userId == null) return;
  try {
    await client.query(
      `INSERT INTO notifications (user_id, type, title, body, league_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [userId, type, title, body, leagueId]
    );
  } catch (err) {
    // A notification failing to write must never break the action that
    // triggered it (reporting a score, requesting a partner, etc.) — log
    // and move on rather than throw.
    console.error('Failed to create notification:', err);
  }

  // Push send is a separate best-effort step from the DB write above — a
  // missing/invalid token or a down FCM never blocks the in-app
  // notification this function exists to create.
  try {
    const result = await client.query('SELECT fcm_token FROM users WHERE id = $1', [userId]);
    const token = result.rows[0]?.fcm_token;
    if (token) {
      await sendPushNotification({ token, title, body, data: { type, leagueId } });
    }
  } catch (err) {
    console.error('Failed to send push notification:', err);
  }
}

// Drops null/undefined ids and de-dupes — reused so a doubles fan-out
// (e.g. all four match participants) never double-inserts for a player
// who is, say, listed as both a recipient and the actor.
function uniqueRecipientIds(userIds) {
  return [...new Set(userIds.filter((id) => id != null))];
}

async function createNotifications(client, userIds, opts) {
  for (const userId of uniqueRecipientIds(userIds)) {
    await createNotification(client, { userId, ...opts });
  }
}

module.exports = { createNotification, createNotifications, uniqueRecipientIds };
