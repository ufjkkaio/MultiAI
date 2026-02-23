# ローンチまでのロードマップ

**現在**: ローカルでバックエンド・iOS アプリともに動作確認済み（開発用ログインスキップでチャット送受信まで確認済み）。

ここから本番公開までにやることを**順番**にまとめています。並行できるものは「並行可」としています。

---

## フェーズ一覧

| 順 | フェーズ | 内容 | 参照 |
|----|----------|------|------|
| 1 | 本番バックエンド | Railway にデプロイし、API URL を取得 | [step-by-step-checklist §4](#4-railway-に登録して本番用バックエンドを用意する) |
| 2 | 利用規約・プライバシーポリシー | ドラフトを仕上げて掲載し、URL をアプリに設定 | 下記「フェーズ2」 |
| 3 | StoreKit 2 課金フロー | サブスク商品の購入・復元・有効判定を実装 | 下記「フェーズ3」 |
| 4 | App Store Connect | アプリ登録・サブスク商品・審査用情報 | 下記「フェーズ4」 |
| 5 | 提出・審査 | ビルドアップロードと審査提出 | 下記「フェーズ5」 |

※ 2 と 3 は並行可。4 は 3 の商品 ID が決まってからがスムーズ。

---

## フェーズ1: 本番バックエンド（Railway）

- **目的**: 本番用 API と DB を用意し、アプリが本番 URL を向けるようにする。
- **手順**（詳細は `docs/step-by-step-checklist.md` の「4. Railway に登録して…」）:
  1. Railway に登録 → 新規プロジェクトで **PostgreSQL** と **Empty Service** を追加。
  2. リポジトリを GitHub に push → Railway で **Deploy from GitHub**（`backend` をルートまたはサブディレクトリとして指定）。
  3. **Variables** に設定:  
     `DATABASE_URL`（PostgreSQL の参照）、`OPENAI_API_KEY`、`GEMINI_API_KEY`、`JWT_SECRET`（本番用に長いランダム文字列）、`APPLE_BUNDLE_ID`（iOS の Bundle ID と一致）、必要なら `MONTHLY_MESSAGE_LIMIT=2000`。
  4. Railway の PostgreSQL で **schema** を実行: `backend/schema.sql` の内容を Query/Data で実行。
  5. バックエンドの **Settings** で **Generate Domain** し、URL を取得（例: `https://xxx.up.railway.app`）。
- **iOS 側**: 本番用ビルドでは `API_BASE_URL` を上記 URL に設定（Scheme の Environment Variables か、本番用 xcconfig などで切り替え）。

---

## フェーズ2: 利用規約・プライバシーポリシー

- **目的**: 審査で求められる「利用規約URL」「プライバシーポリシーURL」を用意し、同意画面から正しくリンクする。
- **手順**:
  1. **ドラフトを仕上げる**  
     - `docs/legal/privacy-policy-draft.md` と `docs/legal/terms-of-use-draft.md` の  
       `[サービス名]`・`[連絡先メールアドレス]`・`[運営者所在地]`・`[日付]` を記入。
  2. **どこかに掲載する**  
     Notion の公開ページ、GitHub Pages、自前サイトなどに貼り、**利用規約の URL** と **プライバシーポリシーの URL** を確定させる。
  3. **アプリの同意画面に反映**  
     `ios/MultiAI/MultiAI/AgreementView.swift` の `termsURL` と `privacyURL` を、上記の**実際の URL** に変更する（現在は `https://example.com/...` のプレースホルダー）。

---

## フェーズ3: StoreKit 2 課金フロー

- **目的**: アプリ内で「1,980円/月」サブスクを購入・復元し、有効な間だけチャットを利用可能にする。
- **前提**: App Store Connect でサブスクリプション商品（1,980円/月）をあらかじめ作成し、**Product ID**（例: `com.multiai.monthly`）を決めておく。
- **実装イメージ**:
  1. **商品の取得**  
     `Product.products(for: ["商品ID"])` でサブスク商品を取得し、価格表示・購入ボタンに利用。
  2. **購入**  
     `Product.purchase()` で購入フローを開始。トランザクションが検証できたら `SubscriptionManager.setSubscriptionActive(true)` を呼び、バックエンドに `POST /subscription/status` で `isActive: true` を送る。
  3. **復元**  
     「購入を復元」ボタンで `Transaction.currentEntitlements` を確認し、対象商品が含まれていれば同様に `setSubscriptionActive(true)`。
  4. **起動時・復帰時**  
     `Transaction.currentEntitlements` で有効なサブスクがあるか確認し、あれば `syncWithBackend()` または `setSubscriptionActive(true)` でサーバーと一致させる。
- **既存コード**: `SubscriptionManager` はすでに `setSubscriptionActive` と `syncWithBackend` を持っている。ここに「StoreKit の結果に応じて呼ぶ」ロジックを追加する。
- **補足**: 本番では App Store Server Notifications でサーバー側にも課金イベントを送る方法もあるが、まずは「アプリがレシートを確認してバックエンドに `isActive` を送る」形でローンチしてもよい（`decisions-and-remaining-considerations.md` の「会員・サブスク」のとおり）。

---

## フェーズ4: App Store Connect の設定

- **目的**: 審査提出に必要なアプリ情報・サブスク商品・スクリーンショットなどを登録する。
- **手順**:
  1. **Apple Developer**  
     有料契約を結び、必要なら Small Business Program を申請。
  2. **App Store Connect**  
     - アプリの新規登録（名前・Bundle ID など）。  
     - **App 内課金**でサブスクリプショングループと商品（1,980円/月）を作成。  
     - **App 情報**でプライバシーポリシー URL・利用規約 URL（フェーズ2で用意したもの）を入力。  
     - 審査用のスクリーンショット・説明文・キーワードを用意して登録。
  3. **iOS 側**  
     StoreKit で使う Product ID が、Connect で作成した ID と一致していることを確認。

---

## フェーズ5: 提出・審査

- **目的**: アーカイブから App Store に提出し、審査に通して公開する。
- **手順**:
  1. Xcode で **本番用 Scheme**（`API_BASE_URL` が Railway の URL）を選び、**Archive**。
  2. **Organizer** から **Distribute App** → App Store Connect にアップロード。
  3. App Store Connect でビルドを選択し、審査に提出。
  4. 審査結果を待ち、指摘があれば修正して再提出。

---

## まとめ（チェックリスト）

- [ ] **1** Railway で DB・バックエンドをデプロイし、本番 URL を取得
- [ ] **2** 利用規約・プライバシーポリシーを仕上げて掲載し、`AgreementView` の URL を差し替え
- [ ] **3** StoreKit 2 で購入・復元・有効判定を実装し、バックエンドと同期
- [ ] **4** App Store Connect でアプリ・サブスク商品・審査用情報を登録
- [ ] **5** アーカイブ→提出→審査対応

細かい手順は `docs/step-by-step-checklist.md` と `docs/decisions-and-remaining-considerations.md` も参照してください。
