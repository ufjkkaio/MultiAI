# Railway プライベートネットワークで Postgres に接続する手順

パブリック接続だと egress（外部転送）コストがかかるため、Railway 内のプライベートネットワークで DB に接続する設定手順です。

---

## 前提

- MultiAI（Node.js バックエンド）と Postgres が**同じプロジェクト・同じ環境**にあること
- プライベート接続は**ランタイム時のみ**有効。ビルド時は使えません

---

## 1. サービス名の確認

Railway で Postgres の**サービス名**を確認します。

1. Railway ダッシュボードでプロジェクトを開く
2. 左のサービス一覧で Postgres の名前を確認（例: `Postgres`、`postgres` など）

内部 DNS は `SERVICE_NAME.railway.internal` です。Postgres なら `postgres.railway.internal`（小文字推奨。大文字で不具合が出るケースあり）。

---

## 2. 変数の参照形式で設定

MultiAI サービスの Variables で `DATABASE_URL` を**変数参照**で設定します。

1. Railway ダッシュボードで **MultiAI** サービスを選択
2. **Variables** タブを開く
3. `DATABASE_URL` を編集（なければ追加）
4. **Value** に以下を入力:

   ```
   ${{Postgres.DATABASE_URL}}
   ```

   ※ Postgres のサービス名が `Postgres` 以外の場合（例: `postgres`）は、実際の名前で:

   ```
   ${{postgres.DATABASE_URL}}
   ```

Railway の Postgres プラグインは次の変数を提供します:

| 変数 | 用途 |
|------|------|
| `DATABASE_URL` | **プライベート**接続（postgres.railway.internal） |
| `DATABASE_PUBLIC_URL` | **パブリック**接続（外部・`railway run` など） |

`${{Postgres.DATABASE_URL}}` はプライベート接続になるため、egress を抑えられます。

---

## 3. ビルド時の注意

プライベートネットワークは**ビルド中は使えません**。

- ビルド時に DB マイグレーション（例: `npm run build` 内で schema 実行）を行う場合は、ビルド用に `DATABASE_PUBLIC_URL` を使う必要があります
- 現在の構成（`railway run npm run db:init` で別途スキーマ実行）であれば、アプリ自体はランタイムで `DATABASE_URL` を使うだけで問題ありません

---

## 4. ランタイムの確認

古いランタイムだと、プライベートネットワーク初期化のタイミングで問題が出ることがあります。

1. MultiAI サービス → **Settings**
2. **Builder** が新しいもの（例: Nixpacks）になっているか確認
3. 必要なら Railway の V2 runtime に移行（Railway の案内に従う）

---

## 5. エラーが出たとき

### ENOTFOUND (postgres.railway.internal)

- 同一プロジェクト・同一環境（例: production）かを確認
- Postgres のサービス名を確認し、`${{Postgres.DATABASE_URL}}` の `Postgres` を実際の名前に合わせる
- サービス名に大文字が含まれる場合は、小文字にした名前（例: `postgres`）を試す

### 起動直後に接続エラー

- プライベートネットワークの初期化に時間がかかる場合があります
- バックエンドに起動遅延や再接続ロジックを入れると安定することがあります（例: 5 秒待ってから DB 接続）

### それでも接続できない

- 一時的に `${{Postgres.DATABASE_PUBLIC_URL}}` に戻して動作確認
- Railway の Help Station やサポートに問い合わせる

---

## 6. ローカル・CLI からの接続

`railway run npm run db:init` など、Railway 外からの接続では**パブリック URL**が必要です。

- ローカル `.env` や `railway run` には `DATABASE_PUBLIC_URL` を使う
- Railway の Postgres の Variables から `DATABASE_PUBLIC_URL` をコピーして利用
