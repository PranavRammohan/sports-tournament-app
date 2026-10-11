-- Standalone ladder mode — see ladderRoutes.js. A persistent, always-on
-- ranked list per sport+city (not tied to any tournament's dates), fully
-- separate from user_sports.rating by design: climbing the ladder never
-- moves your tournament rating, and vice versa — same isolation principle
-- friendly_matches already applies (see migration_friendly_matches.sql),
-- just for a different reason (there it's "nothing at stake"; here it's
-- "this is deliberately its own ranking system").
--
-- Singles only for v1 (doubles ladder needs its own pair-matchmaking
-- problem — a natural v2, not required now).
CREATE TABLE IF NOT EXISTS ladder_members (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sport VARCHAR(20) NOT NULL,
  city VARCHAR(50) NOT NULL,
  position INTEGER NOT NULL,
  joined_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, sport, city)
);
CREATE INDEX IF NOT EXISTS idx_ladder_members_sport_city ON ladder_members (sport, city, position);

-- No real stakes in a friendly match means "whoever reports is final" is
-- fine (see friendly_matches); a ladder result moves your rank, so this
-- follows matches'/playoff_matches' self-report -> other-player-confirms
-- shape instead — status progresses pending -> accepted -> reported ->
-- confirmed (rank moves), with a dispute simply reverting reported back to
-- accepted so a fresh report can be made (no host to arbitrate on a
-- ladder, unlike a tournament match).
CREATE TABLE IF NOT EXISTS ladder_challenges (
  id SERIAL PRIMARY KEY,
  sport VARCHAR(20) NOT NULL,
  city VARCHAR(50) NOT NULL,
  challenger_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  defender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
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
CREATE INDEX IF NOT EXISTS idx_ladder_challenges_pair ON ladder_challenges (challenger_id, defender_id);
