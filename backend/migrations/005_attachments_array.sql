-- 複数画像添付用（最大5枚）。attachments は JSONB 配列: [{ "base64": "...", "media_type": "image/jpeg" }, ...]
-- Run manually: psql $DATABASE_URL -f migrations/005_attachments_array.sql

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS attachments JSONB;
