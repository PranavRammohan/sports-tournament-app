-- Migration: group membership becomes historical (many-to-many), not a single pointer
-- Run this once against your Postgres database before deploying the updated leagueRoutes.js.
--
-- Context: league_members.group_id is a single nullable column — a player can only be in one
-- group at a time, and "advancing" them to a new round previously overwrote it (losing their
-- place in the old group). That's wrong: finishing a group should be additive — a player keeps
-- their seat and full history in every group they've ever played in, and can simultaneously be
-- a member of a new one. This introduces a proper join table for that.

-- 1. A player can belong to any number of groups over the life of a tournament.
CREATE TABLE IF NOT EXISTS group_members (
  id SERIAL PRIMARY KEY,
  group_id INTEGER NOT NULL REFERENCES league_groups(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  joined_at TIMESTAMP DEFAULT now(),
  UNIQUE (group_id, user_id)
);

-- 2. Backfill: preserve whoever is currently assigned before the old column goes away, so no
--    one already placed in a group is silently unassigned by this migration.
INSERT INTO group_members (group_id, user_id)
  SELECT group_id, user_id FROM league_members WHERE group_id IS NOT NULL
  ON CONFLICT (group_id, user_id) DO NOTHING;

-- 3. Retire the superseded single-group column. Only run this AFTER the updated backend is
--    deployed and confirmed working — the old code path reads this column directly, and until
--    it's fully retired there's no harm in leaving it in place unused.
-- ALTER TABLE league_members DROP COLUMN group_id;
