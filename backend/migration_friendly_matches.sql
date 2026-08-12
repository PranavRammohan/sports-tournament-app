-- Friendly (unranked) matches — see friendlyRoutes.js. Deliberately its own
-- table rather than a nullable-league row in `matches`: `matches` and its
-- readers (history, head-to-head, rating-history, checkForRatingDrift,
-- finalizeMatch) all assume a real league, and a friendly match is
-- required to never touch rating/points/matches_played at all. Keeping it
-- fully separate means zero risk of a friendly leaking into any of those
-- existing queries.
--
-- singles only for v1 (format defaults to 'singles' but is still a real
-- column, not a check constraint, so doubles friendlies can be added later
-- without a schema change).
CREATE TABLE IF NOT EXISTS friendly_matches (
  id SERIAL PRIMARY KEY,
  sport VARCHAR(20) NOT NULL,
  format VARCHAR(10) NOT NULL DEFAULT 'singles',
  player1_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  player2_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending/accepted/declined/cancelled/completed
  proposed_time TIMESTAMP,
  venue VARCHAR(200),
  player1_units INTEGER,
  player2_units INTEGER,
  set_scores TEXT,
  winner_id INTEGER REFERENCES users(id),
  reported_by INTEGER REFERENCES users(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_friendly_matches_players ON friendly_matches (player1_id, player2_id);
