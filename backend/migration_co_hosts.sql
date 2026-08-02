-- Migration: add co-host support.
--
-- Context: GAP-06 from the codebase audit — 37 authorization gates across
-- leagueRoutes.js/matchRoutes.js/playoffRoutes.js were all a literal "are
-- you league.created_by," so if the organizer was unavailable nobody else
-- could enter a score or unlock a group. A co-host must already be a league
-- member (they join normally, then the primary host promotes them) — this
-- flag hangs off league_members the same way partner_id/partner_status
-- already does for a different per-member flag. leagues.created_by never
-- changes; a co-host gets the same day-to-day privileges without becoming
-- "the" host.

ALTER TABLE league_members ADD COLUMN IF NOT EXISTS is_co_host BOOLEAN NOT NULL DEFAULT false;
