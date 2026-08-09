-- Byes need no schema change — playoff_matches.status already has no CHECK
-- constraint, so the new 'bye' value (see playoffRoutes.js/leagueRoutes.js's
-- bracket generation) is just another string it already accepts.
--
-- Walkovers: host-entered only (see matchRoutes.js's /report-as-host,
-- /:id/edit and playoffRoutes.js's /report-as-host, /edit-score). No rating
-- change is applied for a walkover — the win/points/advancement register
-- normally, but set_scores stays NULL and this flag is what the mobile UI
-- checks to show "Walkover" instead of a score line.
ALTER TABLE matches ADD COLUMN IF NOT EXISTS is_walkover BOOLEAN DEFAULT false;
ALTER TABLE playoff_matches ADD COLUMN IF NOT EXISTS is_walkover BOOLEAN DEFAULT false;
