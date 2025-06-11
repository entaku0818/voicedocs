# Individual Issues

This directory contains individual issue files split from the main feature-based issue files.

## Issue List

### 録音機能 (Recording Features)
- [Issue #001: 基本録音機能の実装](./issue-001.md) - High Priority
- [Issue #002: 録音ファイル管理機能](./issue-002.md) - High Priority
- [Issue #003: 録音の追加・継続機能](./issue-003.md) - Medium Priority

### 文字起こし機能 (Transcription Features)
- [Issue #004: リアルタイム文字起こし機能](./issue-004.md) - High Priority
- [Issue #005: 録音ファイルの文字起こし機能](./issue-005.md) - High Priority
- [Issue #006: 文字起こし結果の保存機能](./issue-006.md) - High Priority

### 編集機能 (Editing Features)
- [Issue #007: 基本テキスト編集機能](./issue-007.md) - High Priority
- [Issue #008: フィラーワード除去機能](./issue-008.md) - Medium Priority
- [Issue #009: 段落自動整形機能](./issue-009.md) - Medium Priority
- [Issue #010: 編集内容の自動保存](./issue-010.md) - High Priority

### カスタム辞書機能 (Custom Dictionary Features)
- [Issue #011: 基本辞書管理機能](./issue-011.md) - Medium Priority
- [Issue #012: 音声認識への辞書適用](./issue-012.md) - Medium Priority
- [Issue #013: 学習機能](./issue-013.md) - Low Priority

### 話者識別機能 (Speaker Identification Features)
- [Issue #014: 基本話者識別機能（2名まで）](./issue-014.md) - Medium Priority
- [Issue #015: 話者識別結果の管理](./issue-015.md) - Medium Priority
- [Issue #016: 話者識別の手動修正機能](./issue-016.md) - Low Priority

### UI/UX機能 (UI/UX Features)
- [Issue #017: メイン画面のUI実装](./issue-017.md) - High Priority
- [Issue #018: ファイル一覧画面のUI実装](./issue-018.md) - High Priority
- [Issue #019: 設定画面のUI実装](./issue-019.md) - Medium Priority
- [Issue #020: レスポンシブデザイン対応](./issue-020.md) - Medium Priority
- [Issue #021: アクセシビリティ対応](./issue-021.md) - Medium Priority

## Priority Summary

### High Priority (9 issues)
- Issue #001, #002, #004, #005, #006, #007, #010, #017, #018

### Medium Priority (9 issues)
- Issue #003, #008, #009, #011, #012, #014, #015, #019, #020, #021

### Low Priority (2 issues)
- Issue #013, #016

## Labels Summary

### Core Features
- feature, recording, core: #001, #002
- feature, transcription, core: #004, #005, #006
- feature, editing, core: #007
- feature, storage, core: #002, #006, #010
- ui, design, core: #017, #018
- ui, accessibility, core: #021

### Enhancement Features
- feature, recording, enhancement: #003
- feature, editing, smart: #008, #009
- feature, dictionary, integration: #012
- feature, dictionary, ml: #013
- feature, speaker, editing: #016

### Specialized Features
- feature, transcription, realtime: #004
- feature, transcription, batch: #005
- feature, dictionary, core: #011
- feature, speaker, core: #014
- feature, speaker, storage: #015