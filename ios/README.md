# MultiAI iOS アプリ

SwiftUI + Sign in with Apple + チャットUI。サブスクは StoreKit 2 で実装する（本実装は別途追加）。

## 現在の構成（再読み込み済み）

- **Xcode プロジェクト**: `ios/MultiAI/`（MultiAI.xcodeproj）
- **アプリのソース**: `ios/MultiAI/MultiAI/`（Swift ファイル・Assets）
- ターゲット名: **MultiAI**、Bundle ID 例: `multiAI.MultiAI`
- 参考用に `ios/MultiAIApp/` にも同じ Swift ファイルがある場合あり

## 前提

- Xcode 15 以上
- iOS 17 以上をターゲットに推奨

## Signing & Capabilities でやること

- **「+ Capability」** を押し、**「Sign in with Apple」** を追加する。これだけ必須。
- **Debugging Tool** や **Hardened Runtime** のチェックは、シミュレーターを出すために**不要**。そのままでよい。
- Team・Bundle Identifier・Automatically manage signing は、すでに設定されていればそのままでよい。

## バックエンドの URL

**Scheme → Edit Scheme → Run → Arguments** の **Environment Variables** に  
`API_BASE_URL` = `http://localhost:3000`（ローカル）を追加。  
または `APIClient.swift` の `baseURL` を直接書き換え。

## 同意画面のリンク

`AgreementView.swift` の `termsURL` と `privacyURL` を、実際の利用規約・プライバシーポリシーの URL に変更する。

## サブスク（StoreKit 2）

- 本番では App Store Connect でサブスク商品（1,980円/月）を作成し、StoreKit 2 で購入・復元・`currentEntitlements` の確認を行う。
- 購入または復元が成功したら `SubscriptionManager.setSubscriptionActive(true)` を呼び、バックエンドに状態を送る。
- 未購入の場合は `POST /subscription/status` で `isActive: false` が送られ、チャット送信時に 403 となる。

## 開発時のサブスクの代用

バックエンドの `POST /subscription/status` に `{ "isActive": true }` を送ると、そのユーザーは「有料」として扱われる。開発時はアプリからこの API を叩くか、DB で `subscription_status.is_active = true` にするとチャットが使える。
