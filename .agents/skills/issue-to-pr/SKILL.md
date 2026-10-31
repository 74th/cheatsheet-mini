---
name: issue-to-pr
description: GitHub Issueに対応してPRを作成し、人間のレビューと実機確認を経て、PRのマージとIssueのクローズまで進める。ユーザーが「Issue #N に対応してPRを上げて」「このIssueを直して」などと依頼したとき、またはその後のレビュー指摘への対応やマージ・クローズを依頼したときに使う。
---

GitHub Issueの取り込みから、PR作成、人間によるレビュー、マージとIssueのクローズまでを進める。

**Input**: Issue番号またはURL。省略された場合は会話から推測し、特定できなければユーザーに確認する。

## 1. Issueを読む

```bash
gh issue view <N> --json title,body,comments,state,author
```

- `gh issue view <N>` の素の出力は空になることがあるため、`--json` で取得する。
- 要望が複数あれば箇条書きに分解し、それぞれを満たしたかを最後に確認できるようにする。
- 要望が曖昧で実装方針が大きく変わる場合だけユーザーに確認する。それ以外は妥当な解釈で進め、PRに解釈を書く。

## 2. ブランチを作る

```bash
git switch main && git pull --ff-only
git switch -c fix/<short-name>   # 新機能なら feat/<short-name>
```

## 3. 調査と実装

- 原因を特定してから直す。周辺コードのコメント量・命名・書き方に合わせる。
- 挙動が変わる場合は `openspec/specs/` の該当specと `README.md` も更新する。

## 4. 検証とアプリのビルド

```bash
swift build && swift test
./build-app.sh --no-open
pkill -x CheatSheetMini; open "dist/CheatSheet Mini.app"
```

- `swift build` / `swift test` だけでは `dist/CheatSheet Mini.app` は更新されない。ユーザーはこのアプリで動作確認するので、必ずビルドし直して起動し直す。
- UIの挙動はテストで確認できないことが多い。確認できていないことは「未確認」と明記する。

## 5. コミットしてPRを作る

```bash
git add -A
git commit   # 本文に "Fixes #<N>" を含める
git push -u origin <branch>
gh pr create --title "<日本語のタイトル>" --body "<本文>"
```

PR本文の構成:

```markdown
Fixes #<N>

## 変更内容
- 何を、なぜ変えたか（原因を含める）

## 確認
- [x] `swift build` / `swift test` 成功
- [ ] 実機確認: <Issueの要望ごとの確認手順>
```

## 6. 人間にレビューを依頼して止まる

- PRのURL、変更点、実機で確認してほしい手順をユーザーに伝える。
- **ここで止まる。ユーザーの明示的な指示なしにマージしない。**

## 7. フィードバックに対応する

ユーザーから指摘や追加要望があれば、同じブランチで次を繰り返す。

1. 修正し、必要ならspec・READMEも直す
2. 手順4の検証とアプリのビルド・再起動
3. コミットしてpush
4. `gh pr edit <PR> --body ...` でPR本文を最新の挙動に合わせる。ユーザーが確認済みの項目はチェックを付ける
5. 変更点と確認手順を伝えて、再びレビューを待つ

## 8. マージしてIssueをクローズする

ユーザーが動作確認できたと伝え、マージを指示したら実行する。

```bash
gh pr view <PR> --json mergeable,mergeStateStatus,statusCheckRollup
gh pr merge <PR> --rebase --delete-branch   # mainは直線履歴のためrebase merge
gh issue view <N> --json state -q .state
```

- `mergeable` が `MERGEABLE` でない、またはチェックが失敗している場合はマージせずに報告する。
- `Fixes #<N>` でIssueが自動クローズされていなければ、`gh issue close <N> --comment "PR #<PR> で対応しました"` でクローズする。
- 最後にローカルが `main` に戻り、`origin/main` と一致していることを確認して報告する。
