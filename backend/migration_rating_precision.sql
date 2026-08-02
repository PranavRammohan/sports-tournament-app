-- Migration: widen user_sports.rating precision from 1 decimal to 2
-- Run this once against your Postgres (Neon) database before deploying the
-- updated ratingEngine.js/matchRoutes.js/playoffRoutes.js.
--
-- Context: kMax (the max possible rating swing from a single match) works
-- out to roughly 0.65 for tennis and 0.19 for pickleball. Rounding to 1
-- decimal place (numeric(6,1)) throws away nearly all of that signal for
-- pickleball in particular — most results round to 0.0/0.1/0.2, and an
-- expected-result win can move the rating by exactly zero. Badminton
-- (kMax ~105) and table tennis (integer deltas) are unaffected.
--
-- Safe, additive precision widening — every existing 1-decimal value (e.g.
-- 1500.0) is still valid under numeric(6,2), so no backfill is needed.

ALTER TABLE user_sports ALTER COLUMN rating TYPE numeric(6,2);
