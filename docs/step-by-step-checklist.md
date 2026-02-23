# やること一覧（順番に）

**はい。Railway に登録しないと、本番のサーバーを置けないので、本番で動かすなら必要です。** まずはローカルだけで動かすなら、Railway は後回しでもよいです。

---

## 前提：持っているとよいもの

| もの | 必要？ | メモ |
|------|--------|------|
| **Apple Developer アカウント** | 本番アプリを出すなら必須（有料・年額約12,800円） | 審査・Sign in with Apple・サブスクに必要。 |
| **Railway アカウント** | 本番でバックエンドを動かすなら必要 | 無料で登録できる。無料枠あり。 |
| **PostgreSQL** | 必須 | ローカルなら Docker や [Neon](https://neon.tech) 無料枠など。本番なら Railway で追加。 |
| **APIキー（OpenAI・Gemini）** | 必須 | すでに `secrets/.env` に入れている想定。 |

---

## 順番：何をいつするか

### 1. バックエンドをローカルで動かす（まずここ）

1. **Node.js を入れる**  
   [nodejs.org](https://nodejs.org) から LTS をインストール。`node -v` で 18 以上なら OK。

2. **PostgreSQL を用意する**  
   - **案A**: [Neon](https://neon.tech) で無料アカウントを作り、プロジェクト作成。接続 URL（`postgresql://...`）をコピー。
   - **案B**: ローカルに PostgreSQL を入れ、`postgresql://ユーザー:パスワード@localhost:5432/DB名` のような URL を用意。

3. **`secrets/.env` を足す**  
   すでにある `OPENAI_API_KEY` と `GEMINI_API_KEY` に加え、次の行を追加する。
   ```
   DATABASE_URL=postgresql://（Neon やローカルの接続URL）
   JWT_SECRET=なんでもいい長いランダムな文字列
   ```

4. **DB にテーブルを作る**（ここでやることの説明は下の「4 の説明」を見てください）  
   - **Neon の場合**: Neon のサイトにログイン → プロジェクト「multiAI」を開く → 左メニューや画面上で **「SQL Editor」** を開く → `backend/schema.sql` を Cursor で開き、**中身をすべてコピー**（1行目から最後まで）→ SQL Editor の大きな入力欄に**貼り付け** → **「Run」や「Execute」ボタンを押す**。  
   - ローカルならターミナルで:  
     `psql "接続URL" -f backend/schema.sql`

5. **バックエンドを起動する**  
   ターミナルで:
   ```bash
   cd backend
   npm install
   npm run dev
   ```
   `http://localhost:3000/health` をブラウザで開いて `{"ok":true}` が出れば OK。

#### 「4. DB にテーブルを作る」って何をしてるの？

- **DB（データベース）** は、会員情報・ルーム・メッセージなどを**保存する場所**です。Neon で作った「空の DB」には、最初は**保存するための箱（テーブル）がひとつもありません**。
- **テーブル** = データを整理して入れておく表のこと。例: 「users テーブル」＝会員一覧、「messages テーブル」＝会話の内容、など。
- **バックエンドのプログラム**は、「users や messages という名前のテーブルが DB にある」前提で動いています。なので、**先にそのテーブルを DB に作っておく**必要があります。
- **schema.sql** は「users / rooms / messages などのテーブルを作るための設計図（SQL）」が書いてあるファイルです。これを **Neon の SQL Editor で実行する** = Neon の DB に、その設計図どおりのテーブルがひととおり作られます。
- **やることは「schema.sql の全文をコピー → Neon の SQL Editor に貼り付け → Run」** だけです。一度やれば、あとは 5 に進んでバックエンドを起動すればよいです。

---

### 2. 開発用に「サブスク済み」にする（チャットを試すため）

バックエンドは「サブスク有効なユーザー」だけメッセージを送れる。開発中は次のどちらかで有効にする。

- **案A**: アプリでログインしたあと、別ツール（Postman や curl）で  
  `POST http://localhost:3000/subscription/status`  
  に `Authorization: Bearer （ログインでもらったtoken）` と `{"isActive":true}` を送る。
- **案B**: DB を直接触る。Neon の SQL Editor で:  
  `INSERT INTO subscription_status (user_id, is_active) SELECT id, true FROM users LIMIT 1 ON CONFLICT (user_id) DO UPDATE SET is_active = true;`

---

### 3. iOS アプリを Xcode で開いて動かす

1. **Xcode でプロジェクトを開く**  
   - `MultiAI/ios/MultiAI/MultiAI.xcodeproj` を開く（プロジェクト名が MultiAI の場合）。  
   - または自分で新規作成した場合は、そのプロジェクトのソースに `ios/MultiAI/MultiAI/` の Swift が入っている状態にする。

2. **Signing & Capabilities**  
   - **「+ Capability」** → **「Sign in with Apple」** を追加するだけ。  
   - Debugging Tool や Hardened Runtime のチェックは**不要**（シミュレーター表示には関係しない）。

4. **バックエンドの URL を指定する**  
   - シミュレータでローカルに繋ぐ場合: Scheme → Edit Scheme → Run → Arguments の **Environment Variables** に  
     `API_BASE_URL` = `http://localhost:3000`  
   - 実機のときは同じ WiFi で、PC の IP を入れる（例 `http://192.168.1.10:3000`）。または後で Railway の URL を入れる。

5. **実行**  
   シミュレータまたは実機で Run。同意画面 → Sign in with Apple（シミュレータではテスト用 Apple ID）→ ルーム作成 → メッセージ送信（2でサブスク済みにしていれば送れる）。

---

### 4. Railway に登録して本番用バックエンドを用意する（本番で使うとき）

1. **Railway に登録**  
   [railway.app](https://railway.app) で GitHub やメールでアカウント作成。

2. **新規プロジェクト**  
   - New Project → **Add PostgreSQL** で DB を追加。  
   - 同じプロジェクトで **Empty Service** を追加（これがバックエンド用）。

3. **バックエンドのコードをデプロイ**  
   - GitHub に MultiAI を push しておく。  
   - Railway の Empty Service で **Deploy from GitHub** を選び、リポジトリと `backend` をルートにする（またはリポジトリのルートで `backend` をサブディレクトリとして指定する。Railway の設定による）。  
   - **Variables** で次を設定:  
     `DATABASE_URL`（PostgreSQL を追加すると参照が自動で出る）、  
     `OPENAI_API_KEY`、`GEMINI_API_KEY`、`OPENAI_MODEL`、`GEMINI_MODEL`、  
     `JWT_SECRET`（本番用にランダムな長い文字列）、  
     `APPLE_BUNDLE_ID`（iOS の Bundle ID と同じ、例 `com.yourname.multiai`）、  
     （任意）`MONTHLY_MESSAGE_LIMIT`=2000

4. **DB にテーブルを作る**  
   Railway の PostgreSQL → **Data** または **Query** で、`backend/schema.sql` の中身を実行。

5. **URL をメモ**  
   バックエンドの **Settings** で **Generate Domain** などで URL を発行。例: `https://xxx.up.railway.app`。  
   iOS の `API_BASE_URL` をこの URL にすると本番の API に繋がる。

---

### 5. 利用規約・プライバシーポリシーを用意する（審査前に必須）

1. **ドラフトを仕上げる**  
   - `docs/legal/privacy-policy-draft.md` と `terms-of-use-draft.md` の  
     [サービス名]・[連絡先メールアドレス]・[運営者所在地]・[日付] を記入。

2. **どこかに掲載する**  
   - Notion のページ、GitHub Pages、自前サイトなどに貼り、**利用規約のURL** と **プライバシーポリシーのURL** を用意。

3. **アプリの同意画面に反映**  
   - `AgreementView.swift` の `termsURL` と `privacyURL` を、上記の URL に変更。

---

### 6. App Store 用の準備（審査を出す前に）

1. **Apple Developer で**  
   - 有料契約・Small Business Program の申請（任意だが推奨）。

2. **App Store Connect で**  
   - アプリの新規登録。  
   - サブスクリプション商品（1,980円/月）の作成。  
   - 審査用のスクリーンショット・説明文。  
   - プライバシーポリシーURL・利用規約URL の入力。

3. **iOS 側で StoreKit 2 を実装**  
   - サブスク商品の購入・復元・`currentEntitlements` の確認。  
   - 購入（または復元）が有効なときだけ `POST /subscription/status` で `isActive: true` を送る（または App Store Server Notifications でバックエンドが受け取る形にする）。

---

## まとめ：順番だけ

| 順 | やること |
|----|----------|
| 1 | バックエンドをローカルで動かす（Node, PostgreSQL, .env, schema, npm run dev） |
| 2 | 開発用にサブスク済みにする（POST か DB で is_active = true） |
| 3 | iOS を Xcode で開き、Sign in with Apple・API_BASE_URL を設定して実行 |
| 4 | （本番にするとき）Railway に登録して DB・バックエンドをデプロイ、URL を iOS に設定 |
| 5 | 利用規約・プライバシーポリシーを書き、URL を取得して同意画面に設定 |
| 6 | App Store 提出前に、Connect の設定と StoreKit 2 の購入フローを実装 |

**Railway は「本番のサーバーを置くとき」に必要。まずローカルだけで試すなら 1〜3 だけやればよい。**

---

**ローンチまで一気に詰めたいとき** → [launch-roadmap.md](launch-roadmap.md) に「本番デプロイ → 規約URL → StoreKit 2 → Connect → 提出」の順でまとめてあります。
