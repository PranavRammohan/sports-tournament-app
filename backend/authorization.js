// authorization.js
// A plain (non-router) module for the "is this user allowed to act as host
// for this league" check — GAP-06 from the codebase audit. Used by
// leagueRoutes.js, matchRoutes.js, and playoffRoutes.js, the same kind of
// deliberate exception to "route files duplicate small helpers instead of
// sharing a module" as notifications.js/scheduling.js: a genuinely new
// cross-cutting concern, not two files re-implementing the same narrow
// check independently.
//
// `db` is whatever the call site already has in scope — plain `pool`, or a
// transaction `client` inside pool.withTransaction — same zero-branching
// convention as every other shared helper in this codebase.
async function isLeagueAdmin(db, league, userId) {
  if (league.created_by === userId) return true;
  const result = await db.query(
    'SELECT is_co_host FROM league_members WHERE league_id = $1 AND user_id = $2',
    [league.id, userId]
  );
  return result.rows[0]?.is_co_host === true;
}

module.exports = { isLeagueAdmin };
