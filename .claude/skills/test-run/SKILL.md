---
name: test-run
description: VoiceDocs プロジェクトのユニットテストとUIテストを実行します。iPhone 17シミュレータ（iOS 26.1）でテストを実行し、結果をフィルタして表示します。Use when テスト実行、テスト確認、ユニットテスト、UIテスト、テスト失敗。
---

# Test Run Skill

VoiceDocs プロジェクトのテスト実行を自動化。結果を見やすく表示。

## 指示

### Step 1: テスト実行

```bash
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace \
  -scheme voicedocs \
  -configuration Debug \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  2>&1 | grep -E "(Testing completed|BUILD SUCCEEDED|BUILD FAILED|PASSED|FAILED|All tests|Executed.*tests|Test Suite)"
```

**ポイント:**
- iPhone 17 (iOS 26.1)をプライマリテストターゲットとして使用
- フィルタでテスト結果のサマリーのみ表示

### Step 2: テスト結果の分析

**成功の場合:**
```
Test Suite 'All tests' passed at ...
Executed X tests, with 0 failures (0 unexpected) in Y seconds
```
→ ユーザーに成功を報告

**失敗の場合:**
```
Test Suite 'SomeTests' failed at ...
Executed X tests, with Y failures (Z unexpected) ...
```
→ 失敗したテストを特定し、詳細を確認

### Step 3: 詳細ログ確認（失敗時のみ）

```bash
# 最後の10行を確認
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace \
  -scheme voicedocs \
  -configuration Debug \
  test \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' \
  2>&1 | tail -10
```

### Step 4: タスク完了通知

```bash
afplay /System/Library/Sounds/Funk.aiff
```

## 使用例

### 例1: コミット前のテスト確認
```
User: "コミット前にテスト実行して"
Claude: [テスト実行 → 結果確認 → 全てパスしたら承認]
```

### 例2: バグ修正後の検証
```
User: "バグ修正したからテスト通るか確認"
Claude: [テスト実行 → 失敗したテストがあれば詳細を表示]
```

### 例3: リファクタリング後の回帰テスト
```
User: "リファクタリングしたけど既存機能壊してないか確認したい"
Claude: [全テスト実行 → 失敗があればコード変更箇所と照らし合わせ]
```

## トラブルシューティング

### エラー: "Unable to find a destination"
**原因**: iPhone 17 (iOS 26.1) シミュレータが存在しない
**解決方法**: 利用可能なシミュレータを確認して変更
```bash
xcrun simctl list devices available
```

### テストがタイムアウトする
**原因**: UIテストでシミュレータ起動が遅い
**解決方法**: シミュレータを事前起動
```bash
xcrun simctl boot "iPhone 17"
```

### テストが一部スキップされる
**原因**: テストが無効化されている
**解決方法**: Xcodeでテストスキームを確認
1. Product → Scheme → Edit Scheme
2. Test タブでテストが有効か確認

### ビルドは成功するがテストが実行されない
**原因**: build-for-testing のみ実行されている
**解決方法**: `test` コマンドを使用（build-for-testing ではない）

## クイックリファレンス

```bash
# フルテスト実行（全出力）
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'

# テスト結果のみ表示
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' 2>&1 | grep -E "(Testing completed|BUILD SUCCEEDED|BUILD FAILED|PASSED|FAILED|All tests|Executed.*tests|Test Suite)"

# 最後の10行のみ確認
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug test -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' 2>&1 | tail -10

# ビルドのみ（テスト実行なし）
xcodebuild -workspace voicedocs.xcodeproj/project.xcworkspace -scheme voicedocs -configuration Debug build-for-testing -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'

# 利用可能なシミュレータ確認
xcrun simctl list devices available
```
