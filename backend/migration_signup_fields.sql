-- migration_signup_fields.sql
-- One-off, run manually against the DB (no migration framework in this repo,
-- see CLAUDE.md). Adds first/last name, email, and city to `users` so signup
-- collects First Name / Last Name / email / phone / password / city / area /
-- gender instead of a bare username, while keeping `username` itself as the
-- auto-derived "First Last" display name everyone else in the app already
-- reads (leaderboards, schedules, match cards, etc.) — see authRoutes.js.
--
-- Existing accounts have no email; login accepts email OR phone number so
-- they keep working without a forced migration step.

ALTER TABLE users ADD COLUMN first_name varchar(50);
ALTER TABLE users ADD COLUMN last_name  varchar(50);
ALTER TABLE users ADD COLUMN email      varchar(255);
ALTER TABLE users ADD COLUMN city       varchar(50) DEFAULT 'Bangalore';

-- username is now a display name ("First Last"), not a unique handle —
-- multiple people can share a name.
ALTER TABLE users DROP CONSTRAINT users_username_key;

-- Case-insensitive uniqueness, and only enforced where email is actually
-- set, so the existing rows (email IS NULL) don't collide with each other.
CREATE UNIQUE INDEX users_email_lower_key ON users (LOWER(email)) WHERE email IS NOT NULL;

UPDATE users SET city = 'Bangalore' WHERE city IS NULL;
