-- MultiAI Backend: PostgreSQL schema for Railway
-- Run this once when setting up the database.

-- Users (Sign in with Apple の識別子)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_user_id TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscription status (Apple の課金状態をキャッシュ)
CREATE TABLE IF NOT EXISTS subscription_status (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  is_active BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rooms (1ユーザー1ルームで運用する場合も、複数ルーム対応で作成)
CREATE TABLE IF NOT EXISTS rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT DEFAULT '',
  selected_providers TEXT DEFAULT '["openai","gemini"]',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Monthly message count (制限チェック用。月ごとにリセットする想定)
CREATE TABLE IF NOT EXISTS usage_counts (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period TEXT NOT NULL,  -- 'YYYY-MM'
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, period)
);

-- Messages (会話履歴)
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  role TEXT NOT NULL,   -- 'user' | 'assistant'
  provider TEXT,       -- 'openai' | 'gemini' (assistant のみ)
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_rooms_user ON rooms(user_id);
