# リリース手順

Gitタグを切り、ビルド済みアプリのzipをGitHub Releasesに添付してリリースします。Claude Code / Codexではスキル `release`（[.claude/skills/release/SKILL.md](../.claude/skills/release/SKILL.md)）で同じ手順を実行できます。

## バージョンの決まり方

- バージョンはGitタグで決まります。タグ名はバージョンそのもの（例: `0.2.0`）で、`v` は付けません。
- `build-app.sh` がビルド時に `git describe --tags --always --dirty` の結果をアプリ内の `Info.plist` の `CFBundleShortVersionString` に、コミット数を `CFBundleVersion` に書き込みます。この値がメニューバーのメニューに表示されます。
- タグを付けたコミットでは `0.2.0`、タグのないコミットでは `0.1.0-12-gea044fd` のように表示し、未コミットの変更があると `-dirty` が付きます。
- リポジトリの `Info.plist` は書き換えません。リリースのためにバージョンを変えるコミットやPRは不要です。
- 環境変数 `VERSION` を指定すると、その値で上書きできます（例: `VERSION=0.2.0 ./build-app.sh --no-open`）。

## 手順

1. `main` を最新にし、未コミットの変更がないこと、`swift build && swift test` が通ること、同じバージョンのタグがないことを確認します。

   ```bash
   git switch main && git pull --ff-only
   git status --short
   git tag --list
   swift build && swift test
   ```

2. タグを切ります。この時点ではpushしません。

   ```bash
   VERSION=0.2.0
   git tag -a "$VERSION" -m "$VERSION"
   ```

3. アプリをビルドしてzipを作ります。zipは `ditto` で作ります（`zip` コマンドではアプリの署名や属性が壊れることがあります）。

   ```bash
   ./build-app.sh --no-open
   plutil -extract CFBundleShortVersionString raw "dist/CheatSheet Mini.app/Contents/Info.plist"   # $VERSION と一致すること
   rm -f "dist/CheatSheet-Mini-$VERSION.zip"
   ditto -c -k --sequesterRsrc --keepParent "dist/CheatSheet Mini.app" "dist/CheatSheet-Mini-$VERSION.zip"
   ```

   `plutil` で確認したバージョンが `$VERSION` と違う（`-dirty` や `-g<sha>` が付いている）場合は、`git tag -d "$VERSION"` でタグを消してやり直します。

4. タグをpushし、zipを添付したリリースを作ります。

   ```bash
   git push origin "$VERSION"
   gh release create "$VERSION" "dist/CheatSheet-Mini-$VERSION.zip" \
     --title "$VERSION" --verify-tag --notes "<リリースノート>"
   ```

   リリースノートには前回のタグからのユーザーに見える変更（`git log --oneline <前回のタグ>..$VERSION`）と、READMEの[初回起動の許可手順](../README.md#ダウンロードして使う)への案内を書きます。

## 配布物について

- 添付するファイル名は `CheatSheet-Mini-<バージョン>.zip` です。
- `swift build -c release` で作るReleaseビルドで、Apple Silicon（arm64）専用です。Intel Macには対応しません。
- 対応するのはmacOS 13以降です（`Info.plist` の `LSMinimumSystemVersion`）。
- バンドルIDは `tech.74th.CheatSheetMini` です。設定はこのIDごとに保存されるため、変えると利用者の設定が消えます。
- Developer ID署名とAppleの公証は行っていません（ad-hoc署名のみ）。そのため利用者は初回起動時に許可が必要です。
