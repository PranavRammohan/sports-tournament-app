-- GAP-12 — league capacity (batch 9). NULL means uncapped, matching every
-- other optional league-config column (min_rating/max_rating etc).
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS max_players INTEGER;
