-- Self-service blocking — see blocking.js/blockRoutes.js. Added alongside
-- the friendly-match "find players near your rating" feature: that's
-- stranger-to-stranger discovery, and blocking is the minimum safety
-- mechanism for a feature like that. Deliberately scoped narrow: blocking
-- only affects player discovery (search/nearby) and friendly-match
-- challenges — it never hides a blocked player from a tournament you're
-- both already in, a different trust model this doesn't touch.
CREATE TABLE IF NOT EXISTS blocked_users (
  id SERIAL PRIMARY KEY,
  blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker ON blocked_users (blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON blocked_users (blocked_id);
