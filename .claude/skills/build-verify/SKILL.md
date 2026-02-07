---
name: build-verify
description: コード変更後にXcodeビルドを実行して、コンパイルエラーや警告を確認します。-skipMacroValidationフラグを使用してComposableArchitectureマクロの検証をスキップします。Use when ビルド確認、コンパイル、ビルドエラー、変更後の検証。
---

# Build Verify Skill

コード変更後のビルド検証を自動化。ComposableArchitectureマクロ対応。

## 指示

### Step 1: 標準ビルド実行

```bash
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace \
  -scheme voicedocs \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation \
  build 2>&1 | grep -E "(error:|warning:|FAILED|SUCCEEDED)"
```

**ポイント:**
- `-skipMacroValidation`: ComposableArchitectureマクロの検証をスキップ（必須）
- `grep -E`: エラー、警告、ビルド結果のみを表示

### Step 2: ビルド結果の確認

**成功の場合:**
```
** BUILD SUCCEEDED **
```
→ ユーザーに「ビルド成功しました」と報告

**失敗の場合:**
```
error: [エラー内容]
** BUILD FAILED **
```
→ エラー内容を分析し、xcode-debugスキルを提案

### Step 3: タスク完了通知

```bash
afplay /System/Library/Sounds/Funk.aiff
```

## 使用例

### 例1: 機能追加後のビルド検証
```
User: "新しいViewを追加したからビルド確認して"
Claude: [ビルド実行 → 結果確認 → 成功/失敗報告]
```

### 例2: リファクタリング後の検証
```
User: "リファクタリングしたけど動くか確認したい"
Claude: [ビルド実行 → エラーがあればデバッグ提案]
```

### 例3: ライブラリ更新後の検証
```
User: "依存関係更新したから確認して"
Claude: [ビルド実行 → 警告やエラーを報告]
```

## トラブルシューティング

### エラー: "Macro implementation not found"
**原因**: `-skipMacroValidation` フラグが欠けている
**解決方法**: 必ず `-skipMacroValidation` を含める

### エラー: "Unable to find a destination matching the provided destination specifier"
**原因**: 指定されたシミュレータが存在しない
**解決方法**: 利用可能なシミュレータを確認
```bash
xcrun simctl list devices available
```

### ビルドが遅い
**解決方法**: クリーンビルドが必要な場合のみ実行
```bash
xcodebuild clean -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs
```

### 警告が多すぎる
**解決方法**: エラーのみにフィルタ
```bash
xcodebuild ... | grep -E "(error:|FAILED|SUCCEEDED)"
```

## クイックリファレンス

```bash
# フルビルド（出力全体）
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build

# エラー/警告のみ
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build 2>&1 | grep -E "(error:|warning:|FAILED|SUCCEEDED)"

# クリーンビルド
xcodebuild clean && xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build
```
