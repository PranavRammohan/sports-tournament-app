// audit.js
// A plain (non-router) module for recording destructive host actions —
// GAP-14 from the codebase audit. Same cross-cutting-concern exception to
// "route files duplicate small helpers instead of sharing a module" as
// notifications.js/authorization.js/scheduling.js: every destructive route
// needs the same one-line call, so it's a shared helper rather than each
// route hand-rolling its own INSERT.
//
// Conventions copied directly from notifications.js's createNotification:
// `db` is duck-typed (plain `pool` or a transaction `client`), and failures
// are swallowed so a logging problem can never break the action being
// logged — an audit trail that occasionally misses an entry is far better
// than an audit trail that takes down the feature it's watching.
async function recordAudit(db, { leagueId, actorId, action, summary = null }) {
  try {
    await db.query(
      `INSERT INTO league_audit_log (league_id, actor_id, action, summary)
       VALUES ($1, $2, $3, $4)`,
      [leagueId, actorId, action, summary]
    );
  } catch (err) {
    console.error('Audit log write failed:', err);
  }
}

module.exports = { recordAudit };
