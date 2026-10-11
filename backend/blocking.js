// blocking.js
// A plain (non-router) module for self-service blocking — used by
// friendlyRoutes.js (challenge-sending, nearby-rating search) and
// sportsRoutes.js (name search), the two player-discovery surfaces a
// blocked player needs to disappear from. Same "genuinely new
// cross-cutting concern gets its own small module" exception as
// authorization.js/privacy.js (see CLAUDE.md) — two different route files
// need the identical "which user ids am I blocked with" check, so it lives
// here once instead of being copy-pasted twice.
//
// Blocking is symmetric by design: if either side blocked the other,
// neither can discover or challenge the other. There's no "blocked me but
// I can still see them" asymmetry to reason about.

// Every user id blockUserId is blocked with, in either direction — for use
// as `AND u.id != ALL($n::int[])` in a discovery query. Returns [] (never
// null) so callers can always safely bind it as an int[] param even when
// nobody's blocked.
async function getBlockedEitherWayIds(db, userId) {
  const result = await db.query(
    `SELECT blocked_id AS other_id FROM blocked_users WHERE blocker_id = $1
     UNION
     SELECT blocker_id AS other_id FROM blocked_users WHERE blocked_id = $1`,
    [userId]
  );
  return result.rows.map((r) => r.other_id);
}

async function isBlockedEitherWay(db, userIdA, userIdB) {
  const result = await db.query(
    `SELECT 1 FROM blocked_users
     WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)
     LIMIT 1`,
    [userIdA, userIdB]
  );
  return result.rows.length > 0;
}

module.exports = { getBlockedEitherWayIds, isBlockedEitherWay };
