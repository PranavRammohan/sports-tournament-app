// scheduling.js
// A plain (non-router) module for cross-league scheduling-conflict checks —
// GAP-03 from the codebase audit. Used by leagueRoutes.js and playoffRoutes.js,
// the same kind of deliberate exception to "route files duplicate small
// helpers instead of sharing a module" as notifications.js: this is a
// genuinely new cross-cutting concern (checking a player's fixtures across
// every league they're in), not two files re-implementing the same narrow
// check independently.
//
// There's no match-duration concept anywhere in this app's schema, so a
// fixed buffer has to stand in for "how long does a match take" — 90 minutes
// is a reasonable single-match ceiling across all four sports and is easy to
// retune later without touching call sites.
const CONFLICT_BUFFER_MINUTES = 90;

// Finds any OTHER scheduled fixture (round-robin or playoff, in ANY league)
// that already has a time within the buffer window of `scheduledTime` for any
// of `userIds`. Returns [] immediately if `scheduledTime` is null — clearing
// a time can't conflict with anything.
async function findSchedulingConflicts(
  pool,
  { userIds, scheduledTime, excludeScheduledMatchId = null, excludePlayoffMatchId = null }
) {
  if (!scheduledTime) return [];
  const ids = [...new Set(userIds.filter((id) => id != null))];
  if (ids.length === 0) return [];

  const result = await pool.query(
    `SELECT sm.id, sm.scheduled_time, sm.venue, l.name AS league_name, 'regular' AS source
       FROM scheduled_matches sm
       JOIN leagues l ON l.id = sm.league_id
      WHERE sm.scheduled_time IS NOT NULL
        AND ($4::int IS NULL OR sm.id != $4)
        AND ABS(EXTRACT(EPOCH FROM (sm.scheduled_time - $1::timestamp))) < $2 * 60
        AND (sm.player1_id = ANY($3::int[]) OR sm.player1_partner_id = ANY($3::int[])
             OR sm.player2_id = ANY($3::int[]) OR sm.player2_partner_id = ANY($3::int[]))
     UNION ALL
     SELECT pm.id, pm.scheduled_time, pm.venue, l.name AS league_name, 'playoff' AS source
       FROM playoff_matches pm
       JOIN leagues l ON l.id = pm.league_id
      WHERE pm.scheduled_time IS NOT NULL
        AND ($5::int IS NULL OR pm.id != $5)
        AND ABS(EXTRACT(EPOCH FROM (pm.scheduled_time - $1::timestamp))) < $2 * 60
        AND (pm.player1_id = ANY($3::int[]) OR pm.player1_partner_id = ANY($3::int[])
             OR pm.player2_id = ANY($3::int[]) OR pm.player2_partner_id = ANY($3::int[]))`,
    [scheduledTime, CONFLICT_BUFFER_MINUTES, ids, excludeScheduledMatchId, excludePlayoffMatchId]
  );
  return result.rows;
}

module.exports = { findSchedulingConflicts, CONFLICT_BUFFER_MINUTES };
