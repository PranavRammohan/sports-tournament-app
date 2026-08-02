-- Migration: add a guest-player flag to users.
--
-- Context: GAP-05 from the codebase audit — "non-users can't be added at
-- all." A guest gets a real (login-less) users row rather than a parallel
-- placeholder concept, so every existing FK-dependent code path
-- (scheduled_matches/matches/playoff_matches.player1_id etc. all REFERENCE
-- users(id), plus the whole rating engine) works completely unchanged —
-- the only new code is how the row gets created (see leagueRoutes.js's
-- POST /:id/add-guest). email is already nullable and phone_number/
-- password_hash get synthesized placeholder values at creation time, so no
-- other schema change is needed.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT false;
