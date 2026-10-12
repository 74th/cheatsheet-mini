## Why

既存のチートシートでは、相対パスのSVGを `<img src="./electronic_work/Pch-MOSFET-AS-Diode.svg" width="80%">` で参照している。現在のMarkdown変換は生HTMLを除去するため、後段の画像埋め込み処理に届かず、文書を書き換えずに回路図を参照できない。

## What Changes

- Markdown本文のHTML画像タグで指定した相対パスのローカル画像を表示する。
- `width="80%"` などの幅指定を反映し、プレビュー幅を超えないように表示する。
- 従来のMarkdown画像記法と、対応形式・サイズ・参照範囲の制約を維持する。
- コードブロックとinline code内の画像タグはコードとして表示し、画像へ変換しない。
- 対象外の生HTML全般を有効化せず、画像表示に必要なタグと属性のみを扱う。

## Capabilities

### New Capabilities

なし。

### Modified Capabilities

- `markdown-preview`: 相対画像の要件をHTMLの画像タグにも拡張し、幅指定・コード中の扱いを明示する。

## Impact

- 対象は `Sources/CheatSheetMini/Application.swift` のMarkdownからプレビューHTMLを生成する経路と関連テスト、画像表示の利用者向け案内。
- 既存のDownとローカル画像埋め込みを利用し、文書、SVG、保存設定、インデックス形式の移行は不要。
- `openspec/README.md` にある相対画像の実装制約を維持する。一般的な相対画像表示は既存要件だが、生HTMLの画像タグと幅指定のサポートは今回明示的に追加する仕様変更である。
- 非目標: 任意のHTML・JavaScript・CSSの実行、外部画像の仕様変更、SVGの編集、親フォルダや絶対パスの画像への対応、画像形式・サイズ制限の拡張、検索順位・構文・更新タイミングの変更。既知のテーブルやキーボード操作の差異も対象外。
