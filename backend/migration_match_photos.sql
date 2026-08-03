-- GAP-17 — match photos (batch 9). Follows the same base64 data-URI
-- approach already used for profile pictures (see server.js's
-- express.json({limit}) comment and utils.dart's pickProfileImageAsDataUri):
-- stored as plain text, carried in the JSON request body, no separate file
-- upload endpoint or object storage needed.
ALTER TABLE matches ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE playoff_matches ADD COLUMN IF NOT EXISTS photo_url TEXT;
