# AGENTS.md

## 言語

ユーザーへの返答は日本語で書くこと。PRのタイトルと本文、Issueへのコメントも日本語で書く。

## 作業後のビルド

コードを変更する作業を終えたら、必ず `./build-app.sh --no-open` を実行して `dist/CheatSheet Mini.app` を最新のビルドに更新し、起動中のアプリを終了してから起動し直すこと。ユーザーはこのアプリで動作確認するので、ビルドから再起動までエージェントが済ませておくと、ユーザーはすぐに検証できる。

```bash
./build-app.sh --no-open
pkill -x CheatSheetMini; while pgrep -x CheatSheetMini >/dev/null; do sleep 0.2; done
open "dist/CheatSheet Mini.app"
```

- `swift build` / `swift test` だけでは `dist/` のアプリは更新されない
- 終了を待たずに `open` すると `_LSOpenURLsWithCompletionHandler() failed with error -600` で起動に失敗することがあるため、プロセスが消えるまで待つ
- Finderに表示される `CheatSheet Mini.app` の更新日時はビルドしても変わらない。最新かどうかは `Contents/MacOS/CheatSheetMini` の更新日時と、`ps -o lstart -p $(pgrep -x CheatSheetMini)` の起動時刻で確認する
- `dist/` は `.gitignore` 対象のためコミットしない

## プレビューに埋め込むJavaScript

プレビューの `WKWebView` に注入するスクリプトはSwiftの複数行文字列に書いている。

- Swiftの文字列では `\n` が実際の改行になるため、JavaScript側で `\n` を使うときは `\\n` と書く。これを誤るとスクリプト全体が構文エラーで動かず、画面上は何も起きない
- スクリプトを変更したら `Tests/CheatSheetMiniTests/CodeCopyScriptTests.swift` のようにJavaScriptCoreで実行するテストで、構文エラーがないことと動作を確認する

## サードパーティの素材

アイコンなど外部の素材を取り込むときは、無料で使えるライセンスか確認し、ライセンス文を `THIRD_PARTY_NOTICES.md` に追記する。`THIRD_PARTY_NOTICES.md` は `build-app.sh` でアプリにも同梱している。ソースに埋め込む場合は、出典とバージョンをコメントに書く。

## スキルのメンテナンス

スキルはClaude Code用の `.claude/skills/` とCodex用の `.agents/skills/` の両方に置いている。スキルを追加・変更するときは、必ず両方を同じ内容に更新すること。

- 独自スキル: `issue-to-pr`（Issue対応からPR作成、レビュー、マージ、Issueクローズまで）
- `openspec-*` スキルはOpenSpec CLIが生成するため手で編集しない
