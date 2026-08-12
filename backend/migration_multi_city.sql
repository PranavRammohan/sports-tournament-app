-- Multi-city support. users.city existed once and was deliberately dropped
-- (see migration_drop_dead_columns.sql) because it was always hardcoded to
-- the literal string 'Bangalore' and never read for any logic. It's back
-- now because it's actually read this time: browse recommendations
-- (leagueRoutes.js's GET / "nearby" sort) rank a tournament's city against
-- the requester's own city, and area pickers (mobile/lib/constants/
-- areas.dart's areasByCity) are scoped per city.
--
-- Every existing row genuinely is Bangalore (the app only supported one
-- city until now), so backfilling to that literal is factually correct,
-- not a placeholder guess — same reasoning migration_signup_fields.sql
-- used for the same backfill previously.
ALTER TABLE users ADD COLUMN IF NOT EXISTS city VARCHAR(50);
ALTER TABLE leagues ADD COLUMN IF NOT EXISTS city VARCHAR(50);

UPDATE users SET city = 'Bangalore' WHERE city IS NULL;
UPDATE leagues SET city = 'Bangalore' WHERE city IS NULL;

CREATE INDEX IF NOT EXISTS idx_leagues_sport_city ON leagues (sport, city);
