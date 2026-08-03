-- GAP-15 — announcements board (batch 9). Scoped down from full messaging to
-- a one-way board: host/co-host posts, members read. Fans out over the
-- existing notifications infra (notifications.js) rather than inventing a
-- second delivery mechanism.
CREATE TABLE IF NOT EXISTS league_announcements (
  id SERIAL PRIMARY KEY,
  league_id INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id),
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_announcements_league ON league_announcements(league_id, created_at DESC);
