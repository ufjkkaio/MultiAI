-- パーソナライズ（プロフィール・返答スタイル）用
-- Run manually: psql $DATABASE_URL -f migrations/003_add_user_preferences.sql

CREATE TABLE IF NOT EXISTS user_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  profile TEXT DEFAULT '',
  response_style TEXT DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
