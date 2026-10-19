-- Closes a real race: every join-code call site (league creation, the
-- private-mode toggle, league clone — see leagueRoutes.js's
-- withUniqueJoinCode) previously did a check-then-use SELECT before
-- inserting/updating, with nothing at the database level actually
-- preventing two concurrent requests from both passing that check and
-- landing on the same code. This constraint is the real source of truth;
-- withUniqueJoinCode retries with a fresh code on the rare real collision
-- instead of surfacing a raw 500.
--
-- NULL-safe: a public league's join_code is NULL, and Postgres allows
-- unlimited NULLs through a UNIQUE constraint (NULL is never considered
-- equal to another NULL), so this only constrains the private leagues
-- that actually have a code.
ALTER TABLE leagues DROP CONSTRAINT IF EXISTS leagues_join_code_key;
ALTER TABLE leagues ADD CONSTRAINT leagues_join_code_key UNIQUE (join_code);
