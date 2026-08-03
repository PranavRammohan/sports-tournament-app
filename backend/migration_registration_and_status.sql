-- Tech debt (batch 9) — leagues.registration_start, registration_end, and
-- status are read and written by live code (leagueRoutes.js) but no
-- migration file ever created them; they were hand-applied to prod at some
-- point (see GAP-02/registration-window work). Written with IF NOT EXISTS so
-- this is a no-op against prod and makes a fresh database reproducible.
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS registration_start TIMESTAMP;
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS registration_end TIMESTAMP;
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';
