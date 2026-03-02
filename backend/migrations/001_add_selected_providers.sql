-- Add selected_providers to rooms (default: both)
-- Run manually: psql $DATABASE_URL -f migrations/001_add_selected_providers.sql

ALTER TABLE rooms
ADD COLUMN IF NOT EXISTS selected_providers TEXT DEFAULT '["openai","gemini"]';
