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

## 3. GitHub で Pages を有効化する

1. https://github.com/ufjkkaio/MultiAI を開く
2. **Settings** タブをクリック
3. 左メニューの **「Pages」** をクリック
4. **「Build and deployment」** の **Source** で **「Deploy from a branch」** を選ぶ
5. **Branch** で `main` を選び、**Folder** で `/docs` を選ぶ
6. **Save** を押す

数分待つと、`https://ufjkkaio.github.io/MultiAI/` で公開される。

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

これでフェーズ2は完了。
