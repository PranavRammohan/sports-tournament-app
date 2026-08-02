-- Migration: add an in-app notifications table.
--
-- Context: GAP-01 from the codebase audit — there was no notification
-- infrastructure of any kind (push, email, or SMS), and two concrete gaps
-- fell out of that: partner requests (select-partner/respond-partner)
-- produce no signal anywhere, and the existing Pending-tab badge only
-- refreshes on app launch or when you switch to that tab. This table is
-- the in-app half of fixing that — no push/FCM yet, since that needs the
-- app's bundle ID renamed off the com.example.mobile placeholder and a
-- Firebase project set up outside this environment first. Once that's
-- done, the createNotification/createNotifications call sites in
-- notifications.js become the exact points a push send bolts onto.
--
-- league_id cascades so a deleted league's notifications clean up
-- automatically, same reasoning as migration_fk_cascades.sql. No match_id
-- FK — matches/playoff_matches are separate tables and the app has no
-- deep-linking yet, so a notification just links back to the league.

CREATE TABLE IF NOT EXISTS notifications (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(40) NOT NULL,
  title VARCHAR(200) NOT NULL,
  body TEXT,
  league_id INTEGER REFERENCES leagues(id) ON DELETE CASCADE,
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications(user_id, read);
