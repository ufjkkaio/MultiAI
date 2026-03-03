-- メッセージへの画像添付用（写真・ファイル）
-- Run manually: psql $DATABASE_URL -f migrations/004_add_message_attachment.sql

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS attachment_base64 TEXT,
ADD COLUMN IF NOT EXISTS attachment_media_type TEXT;
