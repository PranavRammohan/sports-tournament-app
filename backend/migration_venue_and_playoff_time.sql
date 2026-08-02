-- Migration: add a per-fixture venue field, and give playoff_matches a
-- scheduled_time column to match what scheduled_matches already has.
--
-- Context: GAP-02 from the codebase audit. Round-robin fixtures already
-- store/display scheduled_time fine, but there's no venue/court field
-- anywhere in the schema, and knockout/playoff matches have no time column
-- at all -- only round-robin fixtures could be scheduled before this.
-- Venue is per-fixture (not per-league) since a tournament can span
-- multiple courts/venues across its schedule, same reasoning as why
-- scheduled_time is per-fixture rather than a single league-wide field.

ALTER TABLE scheduled_matches ADD COLUMN IF NOT EXISTS venue VARCHAR(200);
ALTER TABLE playoff_matches ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMP WITHOUT TIME ZONE;
ALTER TABLE playoff_matches ADD COLUMN IF NOT EXISTS venue VARCHAR(200);
