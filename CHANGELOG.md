# Changelog

## [0.8.0] - 2026-08-24

### Added
- AIノート機能（オンデバイス生成）
  - 文字起こし結果から「要約」と「アクションアイテム」をワンタップで生成
  - Apple FoundationModels によるオンデバイス推論。音声・文字起こしを外部送信しない
  - Apple Intelligence 非対応端末では専用の案内を表示
  - 生成結果は Core Data の `aiTranscriptionText` に永続化
- ストア用スクリーンショットの自動生成の仕組み

### Fixed
- `fetchVoiceMemo(id:)` が保存済みAIノートを復元しないバグを修正

### Changed
- ストア文言を実際の機能に合わせて是正し、AIノートの説明を追記

## [Unreleased] - 次回リリース予定

### Added
- SpeechAnalyzer API対応 (iOS 26+)
  - Apple純正の高精度オンデバイス文字起こし
  - iOS 26+: SpeechAnalyzerService使用
  - iOS 25以下: WhisperKit使用（従来通り）
  - TranscriptionServiceProtocolによる統一インターフェース

## [0.2.0] - 2025-XX-XX

### Added
- 文字起こし結果コピー機能
- No Speech detectedエラーハンドリング改善
- バナー広告を全画面に追加
- AdMob環境値システム実装
- タイトル編集モーダル化
- AI文字起こし前広告表示機能
