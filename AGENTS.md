# AGENTS.md

## 作業後のビルド

コードを変更する作業を終えたら、必ず `./build-app.sh --no-open` を実行して `dist/CheatSheet Mini.app` を最新のビルドに更新すること。ユーザーはこのアプリで動作確認する。

- `swift build` / `swift test` だけでは `dist/` のアプリは更新されない
- 古いアプリが起動中なら `pkill -x CheatSheetMini` で終了してから `open "dist/CheatSheet Mini.app"` で起動し直す
- `dist/` は `.gitignore` 対象のためコミットしない

## スキルのメンテナンス

スキルはClaude Code用の `.claude/skills/` とCodex用の `.agents/skills/` の両方に置いている。スキルを追加・変更するときは、必ず両方を同じ内容に更新すること。

- 独自スキル: `issue-to-pr`（Issue対応からPR作成、レビュー、マージ、Issueクローズまで）
- `openspec-*` スキルはOpenSpec CLIが生成するため手で編集しない
