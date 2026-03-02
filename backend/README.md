# MultiAI バックエンド（Railway 用）

Node.js + Express + PostgreSQL。チャットAPI・認証・サブスク状態・利用制限を提供する。

## 必要な環境変数

`secrets/.env` に加え、**Railway のダッシュボード**で以下を設定する。

| 変数 | 説明 |
|------|------|
| `DATABASE_URL` | Railway で PostgreSQL を追加すると自動で入る。 |
| `OPENAI_API_KEY` | OpenAI API キー。 |
| `GEMINI_API_KEY` | Google Gemini API キー。 |
| `OPENAI_MODEL` | 例: `gpt-4o-mini`。 |
| `GEMINI_MODEL` | 例: `gemini-3-flash-preview`。 |
| `JWT_SECRET` | 認証トークン用の秘密文字列（本番ではランダムに生成）。 |
| `APPLE_BUNDLE_ID` | iOS アプリの Bundle ID（Sign in with Apple 検証用）。例: `com.yourname.multiai`。 |
| `MONTHLY_MESSAGE_LIMIT` | 月あたりメッセージ上限。未設定時は 2000。 |

## ローカルで動かす

1. PostgreSQL を用意する（例: Docker で `postgres:15`、または Railway のローカル用 URL）。
2. `secrets/.env` に上記の変数を記入。`DATABASE_URL` はローカルの DB の URL にする。
3. スキーマを投入する:
   ```bash
   psql $DATABASE_URL -f schema.sql
   ```
4. 起動:
   ```bash
   cd backend && npm install && npm run dev
   ```
5. `http://localhost:3000/health` で応答があれば OK。

## Railway にデプロイする

1. Railway で新規プロジェクトを作成。
2. 「Add Service」→ 「Empty Service」。
3. 「Add PostgreSQL」で DB を追加。
4. バックエンドのサービスで「Variables」を開き、上記の環境変数を設定。`DATABASE_URL` は PostgreSQL を追加すると参照が自動で入る。
5. GitHub と連携して `backend/` をデプロイするか、`railway up` でアップロード。
6. PostgreSQL の「Data」→ 「Query」で `schema.sql` の内容を実行する（初回のみ）。
7. 既存 DB の場合は、`migrations/001_add_selected_providers.sql` を実行して `selected_providers` カラムを追加する。

## API 概要

- `POST /auth/apple` — body: `{ "identityToken": "..." }` → `{ token, userId }`
- `GET /chat/rooms` — 認証必須。ルーム一覧。
- `POST /chat/rooms` — 認証必須。ルーム作成。
- `GET /chat/rooms/:roomId/messages` — 認証必須。メッセージ一覧。
- `POST /chat/rooms/:roomId/messages` — 認証必須。body: `{ "content": "...", "providers"?: ["openai","gemini"] }`。サブスク有効かつ月上限内のみ成功。
- `PATCH /chat/rooms/:roomId` — 認証必須。body: `{ "name"?: "...", "selected_providers"?: ["openai","gemini"] }`。
- `GET /subscription/status` — 認証必須。`{ isActive: true/false }`
- `POST /subscription/status` — 認証必須。body: `{ "isActive": true }`。アプリが購入状態を連携するときに使用。
