-- Push notifications (FCM) — see push.js. One token per user (overwritten
-- on each new registration); most users have a single phone, so a
-- multi-device-per-user table is more than v1 needs.
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(255);
