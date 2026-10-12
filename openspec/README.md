# OpenSpecでの仕様管理

2026-10-12に `xprivate/spec.md` の既存要件を `specs/` に移行した。
これは次の変更の比較元となる基本仕様であり、新機能の提案や未実装機能の実装ではない。
基本仕様は `## Purpose` と `## Requirements` を持ち、各要件をSHALLとWHEN/THENシナリオで記述する。
変更用の `ADDED / MODIFIED / REMOVED / RENAMED Requirements` は基本仕様には置かない。

## 仕様の配置と元仕様との対応

| Capability | 対象 | `xprivate/spec.md` の節 |
| --- | --- | --- |
| [application-runtime](specs/application-runtime/spec.md) | 対象環境、常駐、メニュー、ローカル動作、非目標、性能・UX優先順位 | 1–2、17、19–25、27 |
| [directory-settings](specs/directory-settings/spec.md) | フォルダ選択、復元、非再帰のファイル対象 | 3、14、20 |
| [markdown-index](specs/markdown-index/spec.md) | エントリ構造、分割、フェンス、起動時・60分・差分・手動更新、F1で更新しない | 4–6、15–18、20 |
| [entry-search](specs/entry-search/spec.md) | ファイル名、ドット構文、見出し、日本語・曖昧検索、優先順位、逐次検索 | 7–9 |
| [search-panel](specs/search-panel/spec.md) | F1、フォーカス、Space、左右表示、キーボード、元ファイル | 7、10–11、19、27 |
| [markdown-preview](specs/markdown-preview/spec.md) | Markdown、コード、テーブル、相対画像 | 12–13 |

元仕様26節の受け入れテスト7件は、上記の検索・分割・画像・更新・非再帰のシナリオに移行した。
22節のソース構成は推奨例であり、ディレクトリ構造を必須要件にはしない。
23節の推奨技術のうち現実の採用技術は `config.yaml` のcontextに記録した。
50ms未満は目標値として扱い、測定済みや厳密な保証とはしない。

## 要件と現在の実装の差異

`specs/` は元仕様の要件を基準とする。以下は移行時に `Sources/CheatSheetMini/Application.swift` と
プロジェクトの `README.md` を読んで確認した実装・制約であり、要件適合の保証ではない。
以下の表は移行時点の記録である。`add-search-settings` の設定・キー変更は下記の追加記録を参照する。今後、既存要件へ実装を合わせるか、仕様自体を変更するかを変更ごとに判断する。

| 項目 | 基本仕様・元仕様 | 移行時の実装・未確認点 |
| --- | --- | --- |
| 検索対象 | 原則ファイル名と `##` 見出し | `rank` は文書タイトルも半分のスコアで検索する。本文は検索しない |
| ファイル名指定と順位 | ファイル名一致を優先し、適切な一致がなければ全見出しへ検索 | ドットなしではファイル名・見出し・文書タイトルを同時に採点する。見出し完全一致120点、ファイル名完全一致60点なので元仕様の順序と異なる。ドットありのファイル名は曖昧一致も許す |
| Enter | 選択項目を決定。決定後の詳細は未定義 | 検索欄の `.onSubmit` は元Markdownを既定アプリで開く |
| ⌘E | 元Markdownを開く | 専用のキー割り当てはない。「元ファイルを開く」ボタンがある |
| ↑↓ | 検索入力後もマウスなしで候補を移動 | 専用キー処理はなくSwiftUI Listに依存。検索欄フォーカス中の操作は実機未確認 |
| テーブル | Markdownテーブルを表示 | Down/CommonMarkを使用。READMEではGFM独自拡張の完全対応を保証しておらず、CSSのtable指定だけでは変換対応を証明できない |
| 相対画像 | 元Markdownの位置基準で表示 | PNG/JPG/JPEG/GIF/WebP/SVGをdata URLに埋め込む。元Markdownのフォルダ配下で標準化後のパスを判定し、15,000,000バイト未満のみを埋め込む。親フォルダへの参照・絶対パス画像は埋め込まない |
| 外部画像 | ローカル参照にネットワーク不要 | HTTP(S)画像は埋め込まずWebKitのロード処理に任せる。外部画像自体の表示は通信に依存する |
| F1 / Space / 速度 | 即座に表示・入力し、全Space・フルスクリーンで利用 | 移行時はCarbon F1登録とNSPanelのSpace設定があり、代替キー設定UIはなかった。現在の変更では既定Cmd+F1・設定UIを実装。実際のフォーカス・Space動作と50ms目標は実機未検証 |

ソースから確認できる追加の挙動:

- 直下の通常ファイルのみを対象とし、隠しファイルを除外する。拡張子 `.MD` も扱う。UTF-8で読み込めないファイルは失敗件数に数える。
- 見出し解析は先頭0〜3個の空白に続く `# ` / `## ` を扱う。見出し前の文章はエントリ化せず、タイトルがなければファイル名を利用する。
- 検索は `.caseInsensitive` / `.diacriticInsensitive` / `.widthInsensitive` を指定したfoldingで正規化する。見出し側の空白区切り語はAND条件、ドットは最初の1つで分割する。
- 空検索は既存エントリを列挙し、UIの候補は最大120件。パネル再表示時は検索語を空にし、先頭候補を選ぶ。
- 手動更新は `scan(force: true)` で全対象ファイルを再解析する。差分キャッシュ再利用は通常の定期更新に適用される。
- パネル下部には再読み込み・元ファイルを開く・設定の操作と件数・最終更新時刻がある。`simplify-settings-entry-points` でパネルとメニューの直接のフォルダ選択を削除し、通常のフォルダ変更は設定画面から行う。初回起動など未設定時のフォルダ選択は維持する。今回の検証結果は [検証記録](changes/archive/2026-10-12-simplify-settings-entry-points/verification.md) を参照する。
- 選択フォルダのbookmarkをUserDefaultsへ保存する。現在はApp Sandboxを有効にしない個人用ビルドを想定する。

## 次の変更を始める

変更内容を伝えて `openspec-propose` スキルでproposal / design / 差分spec / tasksを作成し、
`openspec-apply-change` で実装・検証する。完了後は `openspec-archive-change` で
差分を基本仕様へ反映してアーカイブする。変更は `openspec/changes/<change-name>/` に置く。
基本仕様を更新するだけの場合には `openspec-sync-specs` を使用できる。

```sh
openspec list --specs
openspec validate --specs --strict --no-interactive
```

導入時点ではアクティブなchangeを作成していなかった。`add-search-settings` は2026-10-12に基本仕様へ同期し、実機未確認の記録を保持してアーカイブした。
今回の検証対象は仕様の構造・記述であり、アプリのビルドやmacOS実機操作は実施していない。

## add-search-settings の実装・検証記録

既定キーをCmd+F1へ変更し、メニューの設定画面、項目単位の適用、キー記録、登録失敗の案内、`name.title` のプレースホルダーを追加した。キー登録の成功後に旧キーを解除し、フォルダは検証・bookmark生成後に切り替える。旧 `folderBookmark` と互換性を維持する。実装は `Application.swift`、`Settings.swift`、`FolderAccess.swift` に置く。

差分仕様は基本仕様へ同期済み。元仕様との対応表のF1表記は移行時の記録であり、現在の呼び出し要件は設定済みショートカット（既定Cmd+F1）を使用する。現在のビルド・自動テスト、実機未確認の項目と残タスクは [検証記録](changes/archive/2026-10-12-add-search-settings/verification.md) と [tasks](changes/archive/2026-10-12-add-search-settings/tasks.md) を参照する。元仕様のEnter・⌘E・候補移動・検索順位・Markdown変換の差異は変更していない。

## simplify-settings-entry-points の完了記録

パネル右下とメニューの直接のフォルダ選択を削除し、右下に既存設定画面への入口を追加した。差分仕様3件は2026-10-12に基本仕様へ同期し、ユーザーによる実装確認とアーカイブ指示を受けてアーカイブした。ビルド・既存テスト7件・仕様検証は成功。詳細な実機検証4件は未確認として保持している。詳細は [検証記録](changes/archive/2026-10-12-simplify-settings-entry-points/verification.md) を参照する。
