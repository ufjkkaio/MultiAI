# Railway の環境変数の入れ方（MultiAI バックエンド）

MultiAI サービスが起動するには、**Variables** に次の変数をすべて入れる必要があります。1つでも抜けると「Application failed to respond」になることがあります。

---

## どこで入れるか

1. Railway のダッシュボードで **MultiAI**（バックエンドのサービス）をクリック
2. 上タブの **「Variables」** を開く
3. **「+ New Variable」** または **「Add Variable」** で、下の変数を**1つずつ**追加する

---

## 入れる変数一覧

### 1. `DATABASE_URL`（必須）

**意味**: Postgres への接続文字列。バックエンドが DB に繋ぐために必要。

**値の取り方**:

1. 左の **Postgres** サービス（データベース）をクリック
2. **「Variables」** タブを開く
3. 一覧にある **`DATABASE_URL`** の値をコピー  
   - または **「Reference」** のようなボタンがあれば、`${{Postgres.DATABASE_URL}}` のような**参照形式**をコピー
4. MultiAI の Variables に戻り、**Name**: `DATABASE_URL`、**Value**: コピーした文字列（または参照）を貼り付けて保存

※ 参照形式（`${{Postgres.DATABASE_URL}}`）が使える場合は、それを使うと「Postgres の接続先」が変わっても自動で追従します。

---

### 2. `JWT_SECRET`（必須）

**意味**: ログイン後に発行する JWT トークンを署名するための秘密鍵。漏れると他人のログインを偽装されるので、**本番用は長いランダム文字列**にすること。

**値の例**:  
`a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0`（32文字以上、英数字をランダムに）

**作り方**:  
- ローカルの `secrets/.env` に書いている `JWT_SECRET` を**そのまま使ってもよい**（開発と本番で同じにする場合）  
- 本番だけ別にしたい場合は、新しいランダム文字列を自分で書くか、次のコマンドで生成:  
  `openssl rand -base64 32`

---

### 3. `OPENAI_API_KEY`（必須）

**意味**: OpenAI API を叩くためのキー。ChatGPT の返答に必要。

**値**:  
- OpenAI のサイト（https://platform.openai.com/api-keys）で発行した API キー  
- ローカルの `secrets/.env` の `OPENAI_API_KEY` をコピーして貼り付けてもよい

---

### 4. `GEMINI_API_KEY`（必須）

**意味**: Google AI（Gemini）API を叩くためのキー。Gemini の返答に必要。

**値**:  
- Google AI Studio などで発行した API キー  
- ローカルの `secrets/.env` の `GEMINI_API_KEY` をコピーして貼り付けてもよい

---

### 5. `APPLE_BUNDLE_ID`（必須）

**意味**: Sign in with Apple のトークン検証で使う「アプリの Bundle ID」。iOS の Xcode で設定している Bundle ID と**完全に同じ**にする必要がある。

**値の例**:  
`com.multiai.app` や `com.yourname.multiai` など

**確認方法**:  
Xcode で MultiAI プロジェクトを開く → 左のプロジェクト名をクリック → **TARGETS** の **MultiAI** を選ぶ → **General** タブの **Bundle Identifier** に書いてある文字列をそのまま使う。

---

### 6. 任意（書かなくても動く）

| 変数名 | 意味 | 省略したときの値 |
|--------|------|------------------|
| `OPENAI_MODEL` | 使う OpenAI モデル | `gpt-4o-mini` |
| `GEMINI_MODEL` | 使う Gemini モデル | `gemini-3-flash-preview` |
| `MONTHLY_MESSAGE_LIMIT` | 1ユーザーあたり月のメッセージ上限 | `2000` |
| `NODE_ENV` | 本番かどうか | 未設定なら `development`。本番なら `production` を入れておくとよい |

---

## 入れたあと

**Variables を保存**すると、多くの場合 **自動で再デプロイ**されます。  
されない場合は、**Deployments** タブから **「Redeploy」** を実行してください。

すべて入っていれば、デプロイが成功し、発行した URL（例: `https://xxx.up.railway.app`）にアクセスすると `/health` で `{"ok":true}` が返るようになります。
