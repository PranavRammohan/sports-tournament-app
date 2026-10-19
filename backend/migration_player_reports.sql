-- Report-to-moderator — see reportRoutes.js. No platform-wide admin/
-- moderator role or review-queue UI exists in this app (every "admin"
-- concept is scoped to one league's host/co-host) and building one would
-- be real scope disproportionate to an app this size. Proportionate v1: a
-- report is stored here for a durable record AND emailed straight to
-- support@playmyset.app via the existing email.js/Resend integration, so
-- it's seen immediately without any new review-queue screen.
CREATE TABLE IF NOT EXISTS player_reports (
  id SERIAL PRIMARY KEY,
  reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason VARCHAR(40) NOT NULL,
  details TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_reports_reported ON player_reports (reported_id);
