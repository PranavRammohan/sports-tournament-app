-- Migration: nested groups (groups inside groups)
-- Run this once against your Postgres (Neon) database before deploying the
-- updated leagueRoutes.js / mobile build.
--
-- Context: league_groups was a flat list — no way to express "this group
-- belongs to that tournament" for a large-scale event made up of several
-- sub-tournaments, each itself split into groups. This adds a single
-- self-referencing parent link, turning the flat list into a tree of
-- arbitrary depth (Mega-event -> Tournament -> Division -> Group A).
--
-- A group stays fully playable (own roster, own fixtures) whether or not it
-- has a parent or children — there is no separate "container" type, so
-- every existing row (parent_group_id IS NULL) already behaves exactly as
-- it did before this migration. No backfill needed.

ALTER TABLE league_groups
  ADD COLUMN IF NOT EXISTS parent_group_id INTEGER REFERENCES league_groups(id);

CREATE INDEX IF NOT EXISTS idx_league_groups_parent ON league_groups(parent_group_id);
