-- Tech debt (batch 9) — two columns with zero live readers, dropped last
-- (run this after every other batch 9 migration; nothing else depends on
-- these two columns, but dropping is irreversible so it stays last by
-- convention).
--
-- league_members.group_id: fully superseded by the group_members join table
-- (migration_group_membership_history.sql) — the many-to-many mechanism is
-- the only one any route code reads or writes today. The DROP was originally
-- left commented out in that migration; this finishes it.
ALTER TABLE league_members DROP COLUMN IF EXISTS group_id;

-- users.city: written on signup/profile-edit but never read for any logic,
-- and both mobile call sites hardcoded it to the literal string 'Bangalore'
-- — see the removed city fields in authRoutes.js and
-- signup_screen.dart/edit_profile_screen.dart (batch 9).
ALTER TABLE users DROP COLUMN IF EXISTS city;
