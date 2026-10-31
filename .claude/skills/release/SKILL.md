---
name: release
description: バージョンを上げてGitタグを切り、ビルド済みアプリのzipを添付したGitHub Releaseを作成する。ユーザーが「リリースして」「0.2.0をリリースしたい」「タグを切ってリリースを作って」などと依頼したときに使う。
---

Gitタグ、ビルド済みアプリのzip、GitHub Releaseを作る。人間向けの同じ手順は `docs/release.md` にある。手順を変えたら両方を更新する。

**Input**: リリースするバージョン（例: `0.2.0`）。省略された場合は `gh release list` で前回のバージョンを示し、パッチ・マイナー・メジャーのどれを上げるかユーザーに確認する。

## 命名規則

- タグとリリース名はバージョンそのまま（`0.2.0`）。`v` は付けない（既存の `0.1.0` に合わせる）
- 添付ファイルは `CheatSheet-Mini-<バージョン>.zip`
- バージョンはGitタグで決まる。`build-app.sh` が `git describe --tags` の結果をアプリ内の `Info.plist` の `CFBundleShortVersionString` に、コミット数を `CFBundleVersion` に書き込み、メニューバーのメニューにもこの値が表示される。**リポジトリの `Info.plist` は書き換えない。リリースのためのコミットやPRは不要。**

## 1. 事前確認

```bash
git switch main && git pull --ff-only
git status --short          # 空であること
gh release list
git tag --list
swift build && swift test
```

- 未コミットの変更がある、テストが失敗する、同じバージョンのタグが既にある場合は止めてユーザーに報告する。

## 2. タグを切る（まだpushしない）

```bash
VERSION=0.2.0
git tag -a "$VERSION" -m "$VERSION"
```

- タグを付けたコミットでビルドすると、バージョンがタグそのものになる。手順3のバージョン確認で問題があれば `git tag -d "$VERSION"` で消してやり直す。

## 3. ビルドしてzipを作る

```bash
./build-app.sh --no-open
plutil -extract CFBundleShortVersionString raw "dist/CheatSheet Mini.app/Contents/Info.plist"   # $VERSION と一致すること（-dirty や -g<sha> が付いていないこと）
rm -f "dist/CheatSheet-Mini-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "dist/CheatSheet Mini.app" "dist/CheatSheet-Mini-$VERSION.zip"
```

- zipは `ditto` で作る。`zip` コマンドではアプリの署名や属性が壊れることがある。
- `dist/` は `.gitignore` 対象なのでzipはコミットされない。
- バージョンの確認は `plutil` の結果で行い、ユーザーにメニューの表示を確認してもらう必要はない（ユーザーの判断）。そのままタグのpushに進む。

## 4. タグをpushする

```bash
git push origin "$VERSION"
```

## 5. GitHub Releaseを作る

前回のタグからの変更を `git log --oneline <前回のタグ>..$VERSION` で確認し、日本語のリリースノートを書く。

```bash
gh release create "$VERSION" "dist/CheatSheet-Mini-$VERSION.zip" \
  --title "$VERSION" --verify-tag --notes "<リリースノート>"
```

リリースノートの構成:

```markdown
## 変更点
- ユーザーから見える変更を箇条書きで

## インストール
`CheatSheet-Mini-<バージョン>.zip` をダウンロードして展開し、`CheatSheet Mini.app` を「アプリケーション」フォルダへ移動してください。Appleの公証を受けていないため、初回起動時の許可が必要です。手順は [README](https://github.com/74th/cheatsheet-mini#ダウンロードして使う) を参照してください。Apple Silicon（arm64）用です。
```

## 6. 報告する

```bash
gh release view "$VERSION" --json url,assets -q '.url, .assets[].name'
```

- リリースのURL、添付したzip名、ローカルの `main` が `origin/main` と一致していることを報告する。
