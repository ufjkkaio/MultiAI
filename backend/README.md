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
| `MONTHLY_MESSAGE_LIMIT` | 月あたりメッセージ上限（課金ユーザー）。未設定時は 1200。 |
| `FREE_MESSAGE_ALLOWANCE` | 課金前の無料で使えるメッセージ数（月あたり・テキストのみ）。超えるとサブスク必須。未設定時は 3。 |
| `CHAT_HISTORY_LIMIT` | 会話履歴のメッセージ件数（10往復＝30件）。未設定時は 30。 |

### 上限到達時の動作を確認する

1. ローカルまたはステージングで `MONTHLY_MESSAGE_LIMIT=2` を設定して起動する。
2. アプリでルームを開き、ユーザーが **2通** 送信する（それぞれ送信ボタン1回＝1通としてカウント）。2通目までは通常どおり送信・返信される。
3. **3通目** を送信すると、API が 429 を返し、アプリに「今月の利用上限に達しました」と表示される。送信したメッセージはサーバーに保存されず、AI の返信も行われない。
4. 確認後は `MONTHLY_MESSAGE_LIMIT` を 1200（または本番想定値）に戻す。

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
7. 既存 DB の場合は、`migrations/001_add_selected_providers.sql`、`002_add_expanded_from_id.sql`、`003_add_user_preferences.sql`、`004_add_message_attachment.sql`、`005_attachments_array.sql` を実行する。

## API 概要

- `POST /auth/apple` — body: `{ "identityToken": "..." }` → `{ token, userId }`
- `GET /chat/rooms` — 認証必須。ルーム一覧。
- `GET /chat/search?q=キーワード` — 認証必須。自分のルーム内メッセージを content で検索。最大50件。`{ results: [{ message_id, room_id, room_name, role, provider, content, created_at }, ...] }`。
- `POST /chat/rooms` — 認証必須。ルーム作成。
- `GET /chat/rooms/:roomId/messages` — 認証必須。メッセージ一覧。
- `POST /chat/rooms/:roomId/messages` — 認証必須。body: `{ "content": "...", "providers"?: ["openai","gemini"], "attachments"?: [{ "image_base64": "<base64>", "image_media_type": "image/jpeg" }, ...] }`。画像は最大5枚（image/jpeg, image/png, image/webp, image/heic）。従来の単体 `image_base64` / `image_media_type` も互換で可。サブスク有効かつ月上限内のみ成功。
- `PATCH /chat/rooms/:roomId` — 認証必須。body: `{ "name"?: "...", "selected_providers"?: ["openai","gemini"] }`。
- `DELETE /chat/rooms/:roomId` — 認証必須。ルームと会話履歴を削除（復元不可）。204 No Content。
- `POST /chat/rooms/:roomId/messages/expand` — 認証必須。body: `{ "message_id": "..." }`。Gemini の「さらに詳しく」用。
- `GET /user/preferences` — 認証必須。パーソナライズ（プロフィール・返答スタイル）を取得。
- `PATCH /user/preferences` — 認証必須。body: `{ "profile"?: "...", "response_style"?: "..." }`。
- `GET /subscription/status` — 認証必須。`{ isActive: true/false }`
- `POST /subscription/status` — 認証必須。body: `{ "isActive": true }`。アプリが購入状態を連携するときに使用。
