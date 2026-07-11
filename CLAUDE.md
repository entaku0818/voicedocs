# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Initial Setup

When starting a new Claude Code session with this repository, use the following command to skip file permission checks and enable full access:

```bash
claude --dangerously-skip-permissions
```

**⚠️ Security Note**: This flag bypasses Claude Code's default file permission safety checks. Only use this in trusted development environments where you need full repository access for iOS development tasks.

## Commands

### Building and Running

```bash
# Build the project (ALWAYS RUN THIS AFTER MAKING CODE CHANGES)
# Note: -skipMacroValidation is required for ComposableArchitecture macros to work correctly
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build

# Quick build check with filtered output
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build 2>&1 | grep -E "(error:|warning:|FAILED|SUCCEEDED)"

# Build for testing
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build-for-testing

# Run tests
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test

# Legacy build command (deprecated - use destination-based build above)
# xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -sdk iphonesimulator -arch arm64 build CODE_SIGNING_ALLOWED=NO
```

### Testing

```bash
# Run all tests with specific simulator
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'

# Run tests with result filtering
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' 2>&1 | grep -E "(Testing completed|BUILD SUCCEEDED|BUILD FAILED|PASSED|FAILED|All tests|Executed.*tests|Test Suite)"

# Quick test status check
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' 2>&1 | tail -10

# Available simulators
xcrun simctl list devices available

# Build for testing only (faster)
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug build-for-testing -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
```

**IMPORTANT**: 
- Always run tests before committing code changes to ensure compilation and functionality
- Use iPhone 17 simulator (iOS 26.1) as the primary test target
- Build failures often indicate macro or dependency issues that need resolution

### Development Schemes
- **voicedocsDevelop**: Development build configuration
- **voicedocs**: Production build configuration

## Architecture Overview

**VoiceDocs** is a Japanese-focused voice memo app using SwiftUI + MVVM architecture with Core Data persistence and local AI transcription.

### Key Components

**App Entry Point**: `voicedocsApp.swift`
- Firebase Analytics initialization in custom AppDelegate
- Environment variable loading for AdMob configuration

**View Layer** (SwiftUI):
- `VoiceMemoListView`: Main navigation with memo list
- `VoiceMemoDetailView`: Detail view with playback and AI transcription
- `ContentView`: Recording interface with real-time audio visualization

**Data Layer**:
- Protocol-based controller pattern: `VoiceMemoControllerProtocol`
- Production: `VoiceMemoController` (Core Data)
- Testing: `FakeVoiceMemoController` (in-memory)
- Model: `VoiceMemo` struct as DTO
- Transcription state management: `TranscriptionStatus` enum
- Audio segment management: `AudioSegment` struct with file references

**Audio Processing**: `SpeechRecognitionManager`
- Real-time Japanese speech recognition using `SFSpeechRecognizer`
- Audio recording with `AVAudioEngine`
- Automatic memo saving upon recording completion
- Error handling with `SpeechRecognitionError` enum (conforms to Equatable)

**Transcription System (Dual Engine)**:
The app features two separate transcription engines for different use cases:

1. **Realtime Transcription** (録音中のリアルタイム文字起こし)
   - Engine: Apple Speech Framework (`SFSpeechRecognizer`)
   - Timing: During recording (real-time)
   - Language: ja-JP (Japanese)
   - Accuracy: Medium (optimized for real-time)
   - Storage: `text` field in VoiceMemo
   - Editable: Yes (user can edit in detail view)
   - Location: Upper section in VoiceMemoDetailView

2. **AI Transcription** (高精度AI文字起こし)
   - Engine: WhisperKit (Apple's high-accuracy AI)
   - Timing: Post-recording (manual button trigger)
   - Language: ja (Japanese)
   - Accuracy: High (batch processing)
   - Storage: `aiTranscriptionText` field in VoiceMemo
   - Editable: No (read-only display)
   - Location: Lower section in VoiceMemoDetailView

**Transcription Management**:
- State tracking: none, inProgress, completed, failed
- Quality metrics and confidence scoring
- Error logging and recovery
- Timestamp tracking for transcription events
- Separate storage for realtime vs AI transcription results

### Core Data Model

Single entity **VoiceMemoModel**:
- `id`: UUID
- `title`: String
- `text`: String (realtime transcription - editable)
- `aiTranscriptionText`: String (AI transcription - read-only)
- `createdAt`: Date
- `voiceFilePath`: String (local file reference)
- `transcriptionStatus`: String (none/inProgress/completed/failed)
- `transcriptionQuality`: Float (0.0-1.0 confidence score)
- `transcribedAt`: Date (timestamp of transcription completion)
- `transcriptionError`: String (error message if failed)
- `segments`: Binary (JSON-encoded AudioSegment array)

### Key Technologies
- **SwiftUI + Combine**: Reactive UI with `@ObservableObject`
- **Core Data**: Local data persistence
- **Speech Framework**: Japanese speech recognition
- **WhisperKit**: Local AI transcription
- **Firebase**: Analytics and crash reporting
- **AdMob**: Interstitial ads before transcription

### Localization
- Bilingual support: English/Japanese
- Uses modern `.xcstrings` format
- App names: "Transcribe" / "シンプル文字起こし"

### Environment Configuration
- `ADMOB_KEY` environment variable required
- `GoogleService-Info.plist` for Firebase configuration
- Audio files stored in Documents directory (local-first privacy approach)

### Testing Structure
- Unit tests in `voicedocsTests/`
- UI tests in `voicedocsUITests/`
- Currently minimal test coverage - needs expansion for Core Data operations and speech recognition

### CI/CD

- Xcode Cloud configuration in `ci_scripts/ci_post_clone.sh`
- Disables macro fingerprint validation for consistent builds

## App Store リリース手順

リリース時は以下の手順で行う。**必ずバージョンとリリース内容をユーザーに確認すること。**

### 1. バージョン確認・更新
```bash
# 現在のバージョン確認
grep -A1 'MARKETING_VERSION' voicedocs.xcodeproj/project.pbxproj | head -4

# 最新タグ確認
git tag --sort=-v:refname | head -5
```

ユーザーに以下を確認:
- 新しいバージョン番号（パッチ/マイナー/メジャー）
- リリース内容（変更点のサマリー）

### 2. コミット・タグ・プッシュ
```bash
# バージョン更新
sed -i '' 's/MARKETING_VERSION = X.X.X/MARKETING_VERSION = Y.Y.Y/g' voicedocs.xcodeproj/project.pbxproj

# コミット
git add -A && git commit -m "chore: バージョンY.Y.Yリリース

- 変更内容1
- 変更内容2

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# タグ作成・プッシュ
git tag vY.Y.Y && git push origin main && git push origin vY.Y.Y

# GitHubリリース作成
gh release create vY.Y.Y --title "vY.Y.Y" --notes "## 変更内容
- 変更内容1
- 変更内容2"
```

### 3. アーカイブ作成・App Store Connectアップロード
```bash
# アーカイブ作成
xcodebuild -project voicedocs.xcodeproj -scheme voicedocs -configuration Release -archivePath ./build/voicedocs.xcarchive archive

# ExportOptions.plist作成
cat > /tmp/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>4YZQY4C47E</string>
</dict>
</plist>
EOF

# App Store Connectにアップロード
xcodebuild -exportArchive -archivePath ./build/voicedocs.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates
```

### 4. Fastlaneで審査提出
```bash
# 環境変数読み込み + メタデータアップロード + 審査提出
source fastlane/.env.default && fastlane upload_metadata
```

**注意**: ビルドがApp Store Connectにアップロードされてから審査提出すること。

## Development Guidelines

### Code Implementation Process

1. **Always build after making changes**: Run the build command to verify compilation
2. **Use arm64 architecture**: For M1/M2 Macs, use `-arch arm64` flag
3. **Filter build output**: Use grep to see only errors, warnings, and build status
4. **Code signing**: Use `CODE_SIGNING_ALLOWED=NO` for local builds

### Build Verification

After implementing any feature or fixing any issue, ALWAYS run:

```bash
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -sdk iphonesimulator -arch arm64 build CODE_SIGNING_ALLOWED=NO | grep -E "(error:|warning:|FAILED|SUCCEEDED)"
```

This ensures all code changes compile successfully before marking tasks as complete.

### Task Completion Notification

When completing tasks or returning messages to the user, ALWAYS execute this notification command at the end:

```bash
afplay /System/Library/Sounds/Funk.aiff
```

This provides audio feedback when work is completed.

## Transcription Implementation Details

### Dual Transcription Architecture

VoiceDocs implements a sophisticated dual transcription system to provide both real-time feedback and high-accuracy results:

#### Realtime Transcription Flow
```
🎤 Recording → SpeechRecognitionManager → SFSpeechRecognizer → text field
```
- **File**: `SpeechRecognitionManager.swift`
- **Method**: `transcribeAudioFile(at:)` and `performFileTranscription(url:)`
- **Trigger**: Automatically during recording
- **Processing**: Real-time with partial results
- **UI Update**: ContentView displays live transcription
- **Storage**: Saved to `text` field in Core Data

#### AI Transcription Flow
```
📱 Detail View Button → WhisperKit → aiTranscriptionText field
```
- **File**: `VoiceMemoDetailView.swift`
- **Method**: `transcribeAudio(memo:)` helper function
- **Trigger**: Manual button press in detail view
- **Processing**: Batch processing of entire audio file
- **UI Update**: Detail view shows result in AI transcription section
- **Storage**: Saved to `aiTranscriptionText` field in Core Data

#### Key Implementation Files
1. **SpeechRecognitionManager.swift**: Realtime transcription engine
2. **VoiceMemoDetailView.swift**: AI transcription trigger and UI
3. **VoiceMemoController.swift**: Data persistence for both types
4. **VoiceMemo.swift**: Data model with dual transcription fields

#### Data Separation Strategy
- **Realtime**: `text` field (editable, updated during recording)
- **AI**: `aiTranscriptionText` field (read-only, high accuracy)
- **UI**: Separate sections in detail view for clear distinction
- **Storage**: Both saved independently in Core Data

This architecture allows users to benefit from immediate feedback during recording while also having access to highly accurate transcription results when needed.

## ループ運用（Loop Engineering）

このリポジトリは memo リポジトリのプロダクトループ（企画→開発→リリース→効果測定→再企画）の対象。
ここで働くエージェントは以下の規律に従う。

### 起点
- 実装するのは**ユーザーが起票した issue、または `loop-go` ラベル付き issue のみ**。勝手に仕事を選ばない
- 提案がある場合は実装せず、issue コメントか報告として出す

### ハーネス（検証ゲート）
- 実装は build / test / lint が緑になるまで自己修正する（コマンド: `xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build`（ビルド）/ `xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`（テスト）。lint コマンドは検証手段なし・要整備）
- **緑でない変更を main に入れない**。5回で緑にならなければブランチに残して報告
- 完了報告には実行した検証コマンドと実出力を含める（「たぶん動く」は完了ではない）

### エスカレーション（諦め方の設計）
- 同一 issue に2回挑戦して解けない → `loop-attempted` ラベルを付けて人間へ
- スコープが当初依頼から拡大しそう → 黙って続けず「続けると+N時間 / 切り出すと今すぐ完了」の2択を提示
- 製品挙動の判断（仕様の分かれ道）に当たった → 勝手に決めず、選択肢と推奨を添えて人間へ

### タイムボックス
- 軽微修正30分・機能実装2時間が目安。超える見込みなら途中で現状報告し分割を提案する
- 深い修理（テストスイート全体・インフラ）は issue 化して夜間ループに回すのがデフォルト

### 記録（Persistence）
- 非自明な発見・設計判断は issue かコミットメッセージに残す（次のエージェントの Discovery 入力になる）
- 機能リリース時は対応する提案の「答え合わせキー」をリリースノートに含める（リリース+7日で memo のループが KPI 答え合わせをする）