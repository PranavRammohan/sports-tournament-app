-- Migration: customizable league points (win/loss point values, optional per-group override)
-- Run this once against your Postgres database before deploying the updated
-- leagueRoutes.js / matchRoutes.js. Fully additive — safe to run any time,
-- and defaults preserve today's behavior (2 points for a win, 0 for a loss,
-- for every existing tournament).

-- Tournament-level points config.
ALTER TABLE leagues
  ADD COLUMN IF NOT EXISTS points_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS points_win     INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS points_loss    INTEGER NOT NULL DEFAULT 0;

-- Per-group override. NULL on any of these three means "inherit the
-- league's value for this field" — a group can override just one field
-- (e.g. only points_win) while inheriting the rest.
ALTER TABLE league_groups
  ADD COLUMN IF NOT EXISTS points_enabled BOOLEAN,
  ADD COLUMN IF NOT EXISTS points_win     INTEGER,
  ADD COLUMN IF NOT EXISTS points_loss    INTEGER;

-- Matches already store the winner's awarded points in league_points_awarded.
-- Loser points need their own column so an edited or deleted score can be
-- reversed exactly, without re-deriving what the loser was owed at the time.
ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS league_points_awarded_loser INTEGER;
