# MultiAI

複数AI（ChatGPT + Gemini）とグループチャットできる iOS アプリ。月額 1,980円のサブスク（実質無制限）。

## 構成

- **backend/** — Node.js API（Railway 用）。認証・チャット・サブスク状態・利用制限。
- **ios/MultiAIApp/** — SwiftUI アプリ。同意画面・Sign in with Apple・チャットUI。
- **docs/** — 理念・仕様・単価試算・法務ドラフトなど。
- **secrets/** — API キー等（`.env` は git に含めない）。

## 決まっていること

- 価格: 1,980円/月
- モデル: GPT-4o mini + Gemini 3 Flash（固定）
- 制限: 月 2,000 通（表向きは実質無制限）
- 認証: Sign in with Apple
- 課金: App Store サブスク（Small Business Program 前提）

## 動かす手順（概要）

1. **バックエンド**
   - `backend/README.md` の「必要な環境変数」を `secrets/.env` と Railway に設定。
   - PostgreSQL に `backend/schema.sql` を実行。
   - `cd backend && npm install && npm run dev` でローカル起動。

2. **iOS アプリ**
   - Xcode で新規 App プロジェクトを作成し、`ios/MultiAIApp/` の Swift ファイルで上書き・追加。
   - `ios/README.md` の手順で Sign in with Apple と API_BASE_URL を設定。
   - シミュレータまたは実機で実行。

3. **開発時のチャット利用**
   - 未購入だと 403 になるため、バックエンドの `POST /subscription/status` で `isActive: true` を送るか、DB で `subscription_status` を true にするとチャット可能。

## ドキュメント

- 理念・単価: `docs/vision-and-unit-economics.md`
- 考えること・決定事項: `docs/decisions-and-remaining-considerations.md`
- 利用制限: `docs/usage-limits-policy.md`
- 法務ドラフト: `docs/legal/`
