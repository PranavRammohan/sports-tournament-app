-- GAP-14 — audit trail (batch 9). Nothing today records who did what;
-- destructive host actions (edit/delete a score, remove a player, regenerate
-- a schedule, lock/unlock a group, cancel a bracket) leave zero trace. This
-- is a simple append-only log, not a full before/after diff — good enough to
-- answer "who did this and when," which is the actual complaint in the audit.
CREATE TABLE IF NOT EXISTS league_audit_log (
  id SERIAL PRIMARY KEY,
  league_id INTEGER NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  actor_id INTEGER REFERENCES users(id),
  action VARCHAR(40) NOT NULL,
  summary TEXT,
  created_at TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_league ON league_audit_log(league_id, created_at DESC);
