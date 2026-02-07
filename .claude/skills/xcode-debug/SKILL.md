---
name: xcode-debug
description: Xcodeビルドエラーやテスト失敗を診断・修正します。ComposableArchitecture、SwiftUI、Core Data、Speech Framework特有のエラーに対応。エラーログを分析し、具体的な修正方法を提案します。Use when ビルドエラー、コンパイルエラー、テスト失敗、デバッグ、エラー解決。
---

# Xcode Debug Skill

Xcodeビルドエラーとテスト失敗の診断・修正を支援。VoiceDocs特有の問題に対応。

## 指示

### Step 1: エラーログの取得

```bash
# ビルドエラーの詳細を取得
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace \
  -scheme voicedocs \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation \
  build 2>&1 | grep -A 5 "error:"
```

### Step 2: エラーの分類

**カテゴリ1: マクロエラー**
- `Macro implementation not found`
- `Macro expansion error`
→ `-skipMacroValidation` フラグを追加

**カテゴリ2: SwiftUI/TCAエラー**
- `Type '...' does not conform to protocol 'Reducer'`
- `Cannot find 'Reducer' in scope`
→ ComposableArchitecture importを確認

**カテゴリ3: Core Dataエラー**
- `managedObjectContext must not be nil`
- `Entity '...' not found`
→ Core Dataスタックの初期化を確認

**カテゴリ4: Speech Frameworkエラー**
- `SFSpeechRecognizer not available`
- `Audio session activation failed`
→ Info.plistの権限設定を確認

**カテゴリ5: 依存関係エラー**
- `No such module '...'`
- `Could not find module '...'`
→ パッケージの再解決が必要

### Step 3: エラー修正の実行

エラータイプに応じて適切な修正を実行:

**マクロエラー:**
```bash
# ビルドコマンドに-skipMacroValidationを追加
xcodebuild ... -skipMacroValidation build
```

**依存関係エラー:**
```bash
# パッケージキャッシュをクリア
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build
xcodebuild -resolvePackageDependencies
```

**Core Dataエラー:**
- `voicedocs.xcdatamodeld` の存在確認
- VoiceMemoModel エンティティの確認
- PersistenceController の初期化確認

**Speech Frameworkエラー:**
- `Info.plist` に `NSSpeechRecognitionUsageDescription` があるか確認
- `Info.plist` に `NSMicrophoneUsageDescription` があるか確認

### Step 4: 修正後の検証

```bash
# ビルド検証
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace \
  -scheme voicedocs \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation \
  build 2>&1 | grep -E "(error:|warning:|FAILED|SUCCEEDED)"
```

### Step 5: タスク完了通知

```bash
afplay /System/Library/Sounds/Funk.aiff
```

## 使用例

### 例1: マクロエラーの解決
```
Error: "Macro implementation not found for macro 'Reducer'"
Claude: [エラー分析 → -skipMacroValidation追加 → ビルド再実行]
```

### 例2: 依存関係の問題
```
Error: "No such module 'ComposableArchitecture'"
Claude: [パッケージキャッシュクリア → 依存関係再解決 → ビルド検証]
```

### 例3: Core Dataエラー
```
Error: "Entity 'VoiceMemoModel' not found in model"
Claude: [.xcdatamodeldファイル確認 → エンティティ定義確認 → 修正提案]
```

### 例4: テスト失敗のデバッグ
```
Test Failed: "testVoiceMemoCreation() failed"
Claude: [テストコード読み込み → 失敗原因特定 → 修正方法提案]
```

## トラブルシューティング

### 問題: ビルドは成功するが実行時にクラッシュ
**診断方法:**
1. Xcodeでシミュレータ実行
2. クラッシュログを確認
3. スタックトレースから原因特定

### 問題: マクロエラーが解決しない
**解決方法:**
1. Xcodeを再起動
2. Derived Dataをクリア:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```
3. プロジェクトをクリーンビルド

### 問題: Core Dataマイグレーションエラー
**解決方法:**
1. シミュレータをリセット:
```bash
xcrun simctl erase "iPhone 17"
```
2. アプリデータを削除して再ビルド

### 問題: WhisperKitエラー
**診断方法:**
1. WhisperKitパッケージのバージョン確認
2. モデルファイルの存在確認
3. メモリ使用量の確認（シミュレータで十分なメモリがあるか）

## クイックリファレンス

```bash
# エラー詳細を取得
xcodebuild ... build 2>&1 | grep -A 10 "error:"

# Derived Dataをクリア
rm -rf ~/Library/Developer/Xcode/DerivedData

# パッケージキャッシュをクリア
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build

# 依存関係を再解決
xcodebuild -resolvePackageDependencies

# シミュレータをリセット
xcrun simctl erase "iPhone 17"

# クリーンビルド
xcodebuild clean && xcodebuild ... build
```

## VoiceDocs特有のエラーパターン

### 1. Speech Recognition権限エラー
```swift
// Info.plist に追加必要
<key>NSSpeechRecognitionUsageDescription</key>
<string>音声をテキストに変換するために音声認識を使用します</string>
<key>NSMicrophoneUsageDescription</key>
<string>音声メモを録音するためにマイクを使用します</string>
```

### 2. WhisperKit AI転写エラー
- モデルのダウンロード状態を確認
- シミュレータでメモリ不足の可能性
- 実機テストを推奨

### 3. AdMob環境変数エラー
```bash
# ADMOB_KEY が設定されているか確認
echo $ADMOB_KEY
```

### 4. Firebase初期化エラー
- `GoogleService-Info.plist` の存在確認
- Firebase Analyticsの初期化コード確認
