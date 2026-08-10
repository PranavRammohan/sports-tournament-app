-- Replaces the old "email/username + phone number" self-service password
-- reset (which let anyone who knew a player's phone number — i.e. any of
-- their scheduled opponents, since privacy.js deliberately shows phones to
-- opponents — take over their account) with a real email-verified code flow.
-- See authRoutes.js's POST /forgot-password and POST /reset-password.
--
-- code_hash stores a bcrypt hash of the 6-digit code (same pattern as
-- password_hash), never the code itself. attempts counts failed guesses
-- against this specific row so a code can be locked out independently of
-- rate limiting at the HTTP layer (see server.js's express-rate-limit on
-- /api/auth, which is the first line of defense; this is the second).
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  used_at TIMESTAMP,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);
