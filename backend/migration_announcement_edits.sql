-- Lets a host edit an announcement after posting it. NULL means never
-- edited; the mobile UI shows an "(edited)" marker only when this differs
-- from created_at, rather than adding a separate boolean flag.
ALTER TABLE league_announcements ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;
