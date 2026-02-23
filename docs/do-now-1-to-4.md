# 今やること 1〜4（順番に）

---

## 1. バックエンドを起動する

1. **ターミナル**を開く（Cursor のターミナルでも、Mac の「ターミナル」アプリでもよい）。
2. 次を**1行ずつ**実行する。

   ```bash
   cd /Users/daisu/MultiAI/backend
   npm run dev
   ```

3. 「MultiAI backend listening on port 3000」のような表示が出て、**そのターミナルは動いたまま**にする（閉じない）。
4. ブラウザで **http://localhost:3000/health** を開く。  
   **`{"ok":true}`** と表示されれば 1 は完了。  
   表示されなければ、`secrets/.env` に `DATABASE_URL` と `JWT_SECRET` が入っているか確認する。

---

## 2. アプリからバックエンドの URL を指定する

1. **Xcode** でプロジェクト **MultiAI** を開く。
2. メニュー **Product → Scheme → Edit Scheme…** を選ぶ（または画面上部の「MultiAI」の横のデバイス名をクリック → **Edit Scheme…**）。
3. 左の一覧で **「Run」** をクリック。
4. 上で **「Arguments」** タブをクリック。
5. 下の方の **「Environment Variables」** の **+** ボタンを押す。
6. **Name** に `API_BASE_URL`、**Value** に `http://localhost:3000` と入力する。
7. **Close** で閉じる。

これで 2 は完了。

---

## 3. アプリを実行してログインする

1. Xcode の画面上部で、実行先が **「iPhone 15」や「iPhone 16」などシミュレーター**になっているか確認する。実機だけの場合は、クリックしてシミュレーターを選ぶ。
2. **▶（Run）** を押す（または **Cmd + R**）。
3. シミュレーターが起動したら:
   - **「利用規約とプライバシーポリシーに同意する」** のチェックを入れる → **「同意する」** を押す。
   - **「Sign in with Apple」** を押す。
   - シミュレーターでは **「Apple ID でサインイン」** の画面が出るので、**「サインインしない」／「パスワードを忘れた」などは選ばず**、表示されているテスト用のメールと名前のまま **「続ける」** を押す（または「サインイン」を押す）。
4. ログインできたら **チャット一覧（ルームがありません）** の画面になる。  
   ここまでできれば 3 は完了。

---

## 4. 開発用に「サブスク済み」にしてチャットを送れるようにする

1. **Neon** のサイト（https://console.neon.tech など）にログインする。
2. プロジェクト **multiAI** を開く。
3. 左メニューで **「SQL Editor」** を開く。
4. 次の SQL を**そのままコピー**して、SQL Editor の入力欄に貼り付け、**Run** を押す。

   ```sql
   INSERT INTO subscription_status (user_id, is_active) SELECT id, true FROM users LIMIT 1 ON CONFLICT (user_id) DO UPDATE SET is_active = true;
   ```

5. エラーが出ずに実行できれば 4 は完了。
6. **アプリに戻る**。  
   「最初のルームを作成」を押す → ルームができる → そのルームを開く → メッセージを入力して「送信」を押す。  
   **ChatGPT と Gemini の返信が表示されれば、1〜4 まで問題なく完了している。**

---

## うまくいかないとき

- **1**: `npm run dev` でエラー → `secrets/.env` に `DATABASE_URL` と `JWT_SECRET` があるか確認。Neon の接続文字列は「Show password」で表示したものを貼ったか確認。
- **2**: アプリが「接続できない」→ 2 で `API_BASE_URL` を入れたか、バックエンド（1）が起動したままか確認。
- **3**: シミュレーターが出ない → 実行先で「iPhone 15」などシミュレーターを選ぶ。Sign in with Apple で「続ける」を押す。
- **4**: 送信すると「サブスクリプションが必要」→ 4 の SQL を実行したか、**3 でログインしたあと**に実行したか確認（先に SQL を実行すると、まだ users に誰もいないので、一度 3 でログインしてから 4 を実行する）。
