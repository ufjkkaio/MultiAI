# GitHub Pages で利用規約・プライバシーポリシーを公開する手順

---

## 1. プレースホルダーを記入する

次のファイルを開き、`[ ]` の部分を実際の内容に置き換える。

- `docs/legal/privacy-policy-draft.md`
- `docs/legal/terms-of-use-draft.md`

| プレースホルダー | 入れ替える内容の例 |
|------------------|--------------------|
| `[サービス名]` | MultiAI |
| `[連絡先メールアドレス]` | 例）support@example.com |
| `[運営者所在地]` | 例）東京都〇〇区〇〇 1-2-3 |
| `[日付を入れる]` | 例）2026年2月24日 |

（利用規約の [運営者所在地] は「管轄裁判所」の条項に使われます）

---

## 2. HTML のプレースホルダーを置き換える

次のファイルを開き、**1 で決めた内容**で `[サービス名]`・`[連絡先メールアドレス]`・`[運営者所在地]`・`[日付を入れる]` を置き換える。

- `docs/terms-of-use.html`（利用規約）
- `docs/privacy-policy.html`（プライバシーポリシー）

エディタの「置換」機能を使うと効率的です。

---

## 3. GitHub で Pages を有効化する（カスタムワークフロー利用）

リポジトリに `ios/MultiAI` サブモジュールがあるため、標準の「Deploy from a branch」ではチェックアウトが失敗します。**カスタム GitHub Actions ワークフロー**（`.github/workflows/deploy-pages.yml`）で **docs だけ**をデプロイするようにしています。

1. https://github.com/ufjkkaio/MultiAI を開く
2. **Settings** タブ → 左メニュー **「Pages」**
3. **「Build and deployment」** の **Source** で **「GitHub Actions」** を選ぶ（**「Deploy from a branch」ではない**）
4. このワークフロー（`Deploy docs to GitHub Pages`）は **main の push で docs を更新したとき**、または手動実行で動きます

`.github/workflows/deploy-pages.yml` を main に push したあと、**docs/** 以下を更新して push するか、Actions タブから「Deploy docs to GitHub Pages」を **Run workflow** で実行してください。数分で `https://ufjkkaio.github.io/MultiAI/` に公開されます。

---

## 4. URL を確認する

公開後、次の URL が表示されることを確認する。

- 利用規約: `https://ufjkkaio.github.io/MultiAI/terms-of-use.html`
- プライバシーポリシー: `https://ufjkkaio.github.io/MultiAI/privacy-policy.html`

---

## 5. アプリの同意画面に URL を設定する

`ios/MultiAI/MultiAI/AgreementView.swift` を開き、次のように変更する。

```swift
var termsURL: URL? { URL(string: "https://ufjkkaio.github.io/MultiAI/terms-of-use.html") }
var privacyURL: URL? { URL(string: "https://ufjkkaio.github.io/MultiAI/privacy-policy.html") }
```

---

## 6. アプリ提出時（App Store Connect）でリンクを確認する場所

提出時に次の場所で URL を入力・確認する。

1. **App Store Connect** にログイン → 対象アプリを選択
2. **「アプリ情報」**（App Information）を開く  
   - **「プライバシーポリシー URL」**（必須）に  
     `https://ufjkkaio.github.io/MultiAI/privacy-policy.html` を入力
3. **「App のプライバシー」**や審査メモで利用規約 URL を求められた場合は  
   `https://ufjkkaio.github.io/MultiAI/terms-of-use.html` を記載
4. アプリ内の同意画面（AgreementView）からも同じ URL で利用規約・プライバシーポリシーへリンクされていることを確認する

ブラウザで上記 URL を開き、利用規約・プライバシーポリシーが正しく表示されることを提出前に確認すること。

---

これでフェーズ2は完了。
