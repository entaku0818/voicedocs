# Issue #005: 録音ファイルの文字起こし機能
**Priority**: High
**Assignee**: 
**Labels**: feature, transcription, core, batch

## 概要
保存された録音ファイルを文字起こしする機能を実装する。

## 要件
- [x] 録音ファイルの文字起こし
- [ ] 長時間ファイルの処理対応
- [x] 処理進捗の表示
- [ ] バックグラウンド処理対応
- [ ] 処理の一時停止・再開

## 技術仕様
- AVAudioFile を使用した音声ファイル処理
- Speech Framework での音声認識（SpeechRecognitionManager.recognizeAudioFile実装済み）
- 進捗管理とUI更新（TranscriptionStatus enum で状態管理）
- Background Processing

## 完了条件
- [x] 録音ファイルの文字起こしができる
- [ ] 長時間ファイルが処理できる
- [x] 処理進捗が表示される
- [ ] バックグラウンドで処理できる