-- Migration: per-group tournament formats + retroactive Groups schema documentation
-- Run this once against your Postgres (Neon) database before deploying the
-- updated leagueRoutes.js / playoffRoutes.js.
--
-- Context: the original Groups feature (league_groups table, league_members.group_id,
-- scheduled_matches.group_id, and a set of league-wide group-stage/stage2 columns on
-- `leagues`) was hand-applied to the database and never had a migration file — it predates
-- this one and isn't reflected in current_schema.sql. Steps 1-3 below retroactively document
-- that existing shape (safe no-ops if it's already there); steps 4+ add the new per-group
-- format/lock columns this pass introduces, and the final step retires the now-superseded
-- league-wide columns.

-- 1. The Groups table itself (name only, historically) — documented retroactively.
CREATE TABLE IF NOT EXISTS league_groups (
  id SERIAL PRIMARY KEY,
  league_id INTEGER REFERENCES leagues(id),
  name VARCHAR(100) NOT NULL
);

-- 2. Members belong to at most one group at a time.
ALTER TABLE league_members
  ADD COLUMN IF NOT EXISTS group_id INTEGER REFERENCES league_groups(id);

-- 3. Scheduled (round-robin / matches-per-player) fixtures can belong to a group.
--    NULL has always meant "not part of any group's schedule" (used for the old Stage 2 pool).
ALTER TABLE scheduled_matches
  ADD COLUMN IF NOT EXISTS group_id INTEGER REFERENCES league_groups(id);

-- 4. NEW: format and lock state move from the league (one setting for every group) onto the
--    group itself (each group picks its own format and locks independently).
ALTER TABLE league_groups
  ADD COLUMN IF NOT EXISTS schedule_type VARCHAR(20) NOT NULL DEFAULT 'round_robin'
    CHECK (schedule_type IN ('round_robin', 'matches_per_player', 'knockout', 'custom')),
  ADD COLUMN IF NOT EXISTS matches_per_player INTEGER,
  ADD COLUMN IF NOT EXISTS locked BOOLEAN NOT NULL DEFAULT false;

-- 5. NEW: a group can now choose 'knockout' as its format, so playoff (bracket) matches need
--    to be attributable to a specific group too. NULL = whole-tournament knockout league
--    (unchanged behavior for leagues that aren't using Groups format at all).
ALTER TABLE playoff_matches
  ADD COLUMN IF NOT EXISTS group_id INTEGER REFERENCES league_groups(id);

-- 6. Retire the superseded league-wide settings. These are replaced by:
--      - group_stage_schedule_type/group_stage_matches_per_player -> league_groups.schedule_type/matches_per_player
--      - groups_locked                                            -> league_groups.locked (per group)
--      - stage2_started/stage2_schedule_type/stage2_matches_per_player/group_advance_count
--                                                                  -> POST /:id/groups/advance just creates
--                                                                     a normal (unlocked) group; "Next Round"
--                                                                     is no longer a special league-wide state.
--
--    IMPORTANT: only run this block AFTER the updated backend/mobile are deployed together —
--    the old code paths read these columns directly. If any tournament currently has
--    groups_locked=true or stage2_started=true, confirm that's acceptable to lose before
--    running this (see the plan's "Note on existing data").
ALTER TABLE leagues DROP COLUMN IF EXISTS group_stage_schedule_type;
ALTER TABLE leagues DROP COLUMN IF EXISTS group_stage_matches_per_player;
ALTER TABLE leagues DROP COLUMN IF EXISTS groups_locked;
ALTER TABLE leagues DROP COLUMN IF EXISTS stage2_started;
ALTER TABLE leagues DROP COLUMN IF EXISTS stage2_schedule_type;
ALTER TABLE leagues DROP COLUMN IF EXISTS stage2_matches_per_player;
ALTER TABLE leagues DROP COLUMN IF EXISTS group_advance_count;
