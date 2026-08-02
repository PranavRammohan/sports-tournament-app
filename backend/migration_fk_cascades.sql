-- Migration: fix missing ON DELETE CASCADE on league_groups/group_members
-- Run this once against your Postgres (Neon) database before deploying the
-- updated leagueRoutes.js.
--
-- Context: matches, scheduled_matches, playoff_matches, and league_members
-- all already cascade-delete from leagues. league_groups (added later, by
-- migration_group_formats.sql) never got the same treatment — deleting a
-- league with any group in it hits a foreign-key violation instead, surfaced
-- to the host as a generic 500. Once league_groups rows cascade-delete,
-- group_members needs its own cascade too, or the FK violation just moves
-- one table over.
--
-- scheduled_matches.group_id and playoff_matches.group_id are deliberately
-- left alone here: those rows are already removed via their own existing
-- league_id -> leagues cascade in the same DELETE statement, before Postgres
-- checks the group_id constraint, so no change is needed for the
-- whole-league-delete path. (Deleting a single group while the league lives
-- on is handled separately, in application code, so a group with real
-- confirmed match history can't be silently destroyed by a DB-level cascade.)

ALTER TABLE league_groups DROP CONSTRAINT IF EXISTS league_groups_league_id_fkey;
ALTER TABLE league_groups ADD CONSTRAINT league_groups_league_id_fkey
  FOREIGN KEY (league_id) REFERENCES leagues(id) ON DELETE CASCADE;

ALTER TABLE group_members DROP CONSTRAINT IF EXISTS group_members_group_id_fkey;
ALTER TABLE group_members ADD CONSTRAINT group_members_group_id_fkey
  FOREIGN KEY (group_id) REFERENCES league_groups(id) ON DELETE CASCADE;

-- If either DROP CONSTRAINT above errors because the auto-generated name
-- differs on your database, run \d league_groups / \d group_members in psql
-- to find the real constraint name and substitute it.
