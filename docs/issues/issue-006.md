# Issue #006: 文字起こし結果の保存機能

**Priority**: High
**Assignee**:
**Labels**: feature, storage, core

## 概要

文字起こし結果をCore Dataに保存する機能を実装する。

## 要件

- [x] 文字起こし結果の保存
- [x] 音声ファイルとの関連付け
- [x] タイムスタンプの記録
- [x] 文字起こし状態の管理
- [x] 結果の上書き保存

## 技術仕様

- Core Data でのデータ保存（実装済み）
- VoiceMemo エンティティの拡張（transcriptionStatus, transcriptionQuality, transcribedAt, transcriptionError, segments フィールド追加済み）
- 関連データの整合性保持（VoiceMemoController に文字起こし管理メソッド実装済み）

## 完了条件

- [x] 文字起こし結果が保存できる
- [x] 音声ファイルと関連付けられる
- [x] データの整合性が保たれる

## 実装内容

- `TranscriptionStatus` enum を追加（none/inProgress/completed/failed）
- Core Data モデルに文字起こし関連フィールドを追加
- `VoiceMemoController` に文字起こし状態管理メソッドを実装
  - `updateTranscriptionStatus()`: 状態更新
  - `updateTranscriptionResult()`: 結果と品質保存
  - `updateTranscriptionError()`: エラー情報保存
  - `getTranscriptionStatus()`: 状態取得
- `VoiceMemo` 構造体に文字起こし情報プロパティを追加
- `FakeVoiceMemoController` を新しいインターフェースに対応
