# VoiceDocs

AI文字起こし機能を搭載した、プライバシー重視の音声メモアプリです。日本語処理に最適化されています。

## 機能

- **音声録音**: リアルタイム音声キャプチャと視覚的フィードバック
- **リアルタイム音声認識**: 録音中の日本語音声テキスト変換
- **AI文字起こし**: WhisperKitを使用したオフライン文字起こし
- **ローカルストレージ**: すべてのデータをCore Dataでローカル保存
- **多言語対応**: 英語・日本語ローカライゼーション
- **プライバシー第一**: クラウドストレージなし、すべての処理をデバイス内で実行

## 動作環境

- iOS 15.0以上
- Xcode 15.0以上
- マイクロフォンアクセス許可
- 音声認識アクセス許可

## セットアップ

1. リポジトリをクローン
2. Firebase設定:
   - `GoogleService-Info.plist`をプロジェクトに追加
3. AdMob設定:
   - ビルド設定で`ADMOB_KEY`環境変数を設定
4. Xcodeで`voicedocs.xcodeproj`を開く
5. プロジェクトをビルドして実行

## アーキテクチャ

モダンなiOS開発手法で構築:

- **SwiftUI + MVVM**: リアクティブデータバインディングを使った宣言的UI
- **Core Data**: ローカルデータ永続化
- **プロトコルベース設計**: テスト可能性のための依存性注入
- **Combineフレームワーク**: リアクティブプログラミングパターン

### 主要コンポーネント

- `VoiceMemoListView`: 録音済みメモを表示するメインインターフェース
- `VoiceMemoDetailView`: 再生と文字起こしインターフェース
- `ContentView`: 音声レベル可視化付き録音インターフェース
- `SpeechRecognitionManager`: リアルタイム音声処理
- `VoiceMemoController`: Core Data操作

## 使用技術

- **SwiftUI**: モダンな宣言的UIフレームワーク
- **Speech Framework**: リアルタイム日本語音声認識
- **AVFoundation**: 音声録音・再生
- **Core Data**: ローカルデータ永続化
- **Combine**: リアクティブプログラミング
- **WhisperKit**: ローカルAI文字起こし
- **Firebase Analytics**: 使用状況分析
- **Google Mobile Ads**: 広告収益化

## ビルド

```bash
# 開発用ビルド
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocsDevelop -configuration Debug build

# 本番用ビルド
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Release build

# テスト実行
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs test
```

## プライバシー

VoiceDocsはユーザーのプライバシーを最優先します:

- すべての音声録音をデバイスローカルに保存
- AI文字起こしを完全にオフラインで処理
- 音声データを外部サーバーに送信しない
- Firebase Analyticsはアプリ使用状況のみ（個人データなし）

## ローカライゼーション

- 英語: "Transcribe"
- 日本語: "シンプル文字起こし"

両言語に完全対応し、自動言語検出機能付きの完全ローカライズインターフェース。

## ライセンス

[ライセンス情報をここに追加してください]