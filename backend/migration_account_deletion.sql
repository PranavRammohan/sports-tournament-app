-- GAP-10 — account deletion (batch 9).
--
-- A hard DELETE FROM users is not viable: 22 foreign keys reference users(id)
-- and only 3 of them cascade (league_members, user_sports, notifications) —
-- the other 19 (matches, playoff_matches, scheduled_matches,
-- leagues.created_by, group_members) are NO ACTION, so deleting a user would
-- either fail outright or destroy other players' match history. Instead,
-- DELETE /api/auth/account anonymizes the row in place (see authRoutes.js)
-- and marks it with this column so login/forgot-password can exclude it.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;
