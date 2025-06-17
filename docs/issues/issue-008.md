# Issue #008: フィラーワード除去機能

**Priority**: Medium
**Assignee**:
**Labels**: feature, editing, smart

## 概要

「えー」「あの」などのフィラーワードをワンタップで除去する機能を実装する。

## 要件

- [x] 日本語フィラーワードの検出
- [x] 英語フィラーワードの検出
- [x] ワンタップでの一括除去
- [x] 除去前の確認ダイアログ
- [x] カスタムフィラーワード設定

## 技術仕様

- 正規表現を使った文字列処理（実装済み）
- フィラーワード辞書の管理（FillerWordRemover クラス実装済み）
- プレビュー機能（FillerWordPreviewView 実装済み）

## 完了条件

- [x] フィラーワードが検出できる
- [x] ワンタップで除去できる
- [x] カスタム設定ができる

## 実装内容

- `FillerWordRemover` クラスの実装
  - 日本語・英語のフィラーワード辞書
  - 正規表現による高度なパターンマッチング
  - カスタムパターンの追加・削除機能
- `FillerWordRemovalResult` 構造体で除去結果を管理
- `VoiceMemoController` にフィラーワード除去メソッドを追加
  - `removeFillerWordsFromMemo()`: 実際の除去と保存
  - `previewFillerWordRemoval()`: プレビュー機能
- `VoiceMemoDetailView` にフィラーワード除去ボタンを追加
- `FillerWordPreviewView` でプレビューと確認ダイアログを表示
