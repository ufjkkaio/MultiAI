# GitHub を SSH で使う手順（Mac）

push で「Password authentication is not supported」が出る場合、SSH 鍵を登録するとパスワードなしで push/pull できます。

---

## 1. すでに SSH 鍵があるか確認する

ターミナルで実行：

```bash
ls -la ~/.ssh
```

`id_ed25519` と `id_ed25519.pub`、または `id_rsa` と `id_rsa.pub` があれば鍵はある。**2 に進まず、4 へ**（GitHub に登録済みか 5 で確認）。

何もない、または「No such file」なら **2** へ。

---

## 2. SSH 鍵を新規作成する

```bash
ssh-keygen -t ed25519 -C "あなたのGitHub用メールアドレス"
```

- 「Enter file in which to save the key」→ **Enter だけ**押す（標準の場所で OK）
- 「Enter passphrase」→ 空で Enter、またはパスフレーズを入れて Enter（推奨はパスフレーズあり）

`~/.ssh/id_ed25519`（秘密鍵）と `id_ed25519.pub`（公開鍵）ができる。

---

## 3. ssh-agent に鍵を登録する

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

（鍵を `id_rsa` にした場合は `~/.ssh/id_rsa` に置き換える）

---

## 4. 公開鍵を GitHub に登録する

**4-1. 公開鍵をコピーする**

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

これでクリップボードに公開鍵が入る。

**4-2. GitHub で鍵を追加**

1. https://github.com/settings/keys を開く（ログインしていれば「SSH and GPG keys」）
2. **New SSH key** をクリック
3. **Title**: 例）`MacBook Air`（どの PC の鍵か分かる名前で OK）
4. **Key type**: Authentication Key のまま
5. **Key**: 欄に **貼り付け**（4-1 でコピーした内容）
6. **Add SSH key** をクリック

---

## 5. 接続テスト

```bash
ssh -T git@github.com
```

初回だけ「Are you sure you want to continue connecting?」→ **yes** と入力。

成功すると次のように出る：

```
Hi ufjkkaio! You've successfully authenticated, but GitHub does not provide shell access.
```

---

## 6. リモートを HTTPS から SSH に切り替えて push

MultiAI のフォルダで：

```bash
cd /Users/daisu/MultiAI
git remote set-url origin git@github.com:ufjkkaio/MultiAI.git
git push -u origin main
```

パスワードを聞かれずに push できれば完了。

---

## まとめコマンド（鍵がすでにある場合）

```bash
# リモートを SSH に変更
git remote set-url origin git@github.com:ufjkkaio/MultiAI.git
# push
git push -u origin main
```

鍵がまだの場合は **2 → 3 → 4 → 5 → 6** の順で実施。
