-- Migration: knockout/bracket matches award league points too
-- Run this once against your Postgres database before deploying the updated
-- playoffRoutes.js / leagueRoutes.js. Fully additive — safe to run any time.
--
-- Context: playoff_matches never awarded league points at all, even after
-- the customizable points system was added for round-robin/custom matches
-- (see migration_custom_points.sql). This brings knockout matches (both
-- whole-tournament Playoffs and knockout-format Groups) in line with every
-- other match type — same points_enabled/points_win/points_loss resolution
-- (tournament, optionally overridden per-group), same winner+loser award.

ALTER TABLE playoff_matches
  ADD COLUMN IF NOT EXISTS league_points_awarded INTEGER,
  ADD COLUMN IF NOT EXISTS league_points_awarded_loser INTEGER;
