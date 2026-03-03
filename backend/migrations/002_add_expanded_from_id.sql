-- Add expanded_from_id to messages (Gemini "さらに詳しく" 用)
-- Run manually: psql $DATABASE_URL -f migrations/002_add_expanded_from_id.sql

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS expanded_from_id UUID REFERENCES messages(id) ON DELETE SET NULL;
