# Changelog

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
