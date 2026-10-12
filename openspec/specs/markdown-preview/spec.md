# Markdown Preview Specification

## Purpose

選択したセクションを読みやすいMarkdownとして表示し、コードとローカル画像を含めて即座に参照する。

## Requirements

### Requirement: Markdownのレンダリング
アプリは選択エントリのMarkdownをレンダリングして表示する SHALL。最低限、見出し、段落、箇条書き、コードブロック、inline code、リンク、テーブル、画像に対応する。

#### Scenario: 基本文法を表示する
- **WHEN** 選択セクションに見出し、段落、箇条書き、inline code、リンクがある
- **THEN** 各要素をMarkdownとして表示する

#### Scenario: テーブルを表示する
- **WHEN** 選択セクションにMarkdownテーブルがある
- **THEN** 表として参照できる形で表示する

### Requirement: コードブロックの可読性
アプリはコードブロックの可読性を重視して表示する SHALL。構文強調の採用は必須としない。

#### Scenario: コマンドを読む
- **WHEN** 選択セクションに複数行のコードブロックがある
- **THEN** 行構造を保ち、通常の本文と区別して読みやすく表示する

### Requirement: 相対パスのローカル画像
アプリはMarkdown内の相対パス画像を元Markdownファイルの位置を基準に解決し、プレビュー上で表示する SHALL。インデックスがサブディレクトリを探索しないことは、画像参照先にサブディレクトリを利用できないことを意味しない。現在の画像形式・サイズ・参照範囲の制約は `openspec/README.md` に記録する。

#### Scenario: imagesフォルダの画像を表示する
- **WHEN** `sbx.md` が `![image](images/example.png)` を含み、その相対位置に表示可能な画像が存在する
- **THEN** `sbx.md` のあるフォルダを基準に画像を解決し、プレビューに表示する

#### Scenario: フォルダごとの相対位置
- **WHEN** 別のフォルダにあるMarkdownが同じ `images/example.png` という相対パスを持つ
- **THEN** それぞれの元Markdownの位置を基準に画像を解決する
