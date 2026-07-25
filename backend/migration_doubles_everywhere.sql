-- Migration: doubles gets all formats (knockout + fixed-matches) + self-select/host-manual partners
-- Run this once against your Postgres (Neon) database before deploying the
-- updated leagueRoutes.js / playoffRoutes.js.

-- 1. Playoff (knockout) matches need partner columns, same shape as the `matches` table,
--    so doubles knockout brackets can track both players on each side.
ALTER TABLE playoff_matches
  ADD COLUMN IF NOT EXISTS player1_partner_id INTEGER REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS player2_partner_id INTEGER REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS player1_partner_rating_change NUMERIC,
  ADD COLUMN IF NOT EXISTS player2_partner_rating_change NUMERIC;

-- 2. Leagues need a partner_mode for doubles: how partners get decided.
--    'host_auto'   -> existing algorithmic rating-balancing (unchanged default behavior)
--    'self_select' -> players pick + confirm their own partner before a schedule/bracket can be generated
--    'host_manual'  -> host manually pairs every player before a schedule/bracket can be generated
ALTER TABLE leagues
  ADD COLUMN IF NOT EXISTS partner_mode VARCHAR(20) NOT NULL DEFAULT 'host_auto'
    CHECK (partner_mode IN ('host_auto', 'self_select', 'host_manual'));

-- 3. league_members needs to be able to store a pending/confirmed partner,
--    used only when partner_mode is 'self_select' or 'host_manual'.
--    (Harmless and unused for singles leagues / host_auto doubles leagues.)
ALTER TABLE league_members
  ADD COLUMN IF NOT EXISTS partner_id INTEGER REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS partner_status VARCHAR(20)
    CHECK (partner_status IN ('pending', 'confirmed'));