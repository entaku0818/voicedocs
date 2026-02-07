---
name: release
description: VoiceDocs (シンプル文字起こし) をApp Storeにリリースする手順を実行します。バージョン確認、コミット、タグ作成、アーカイブ、App Store Connectアップロード、審査提出までを自動化します。Use when リリース、App Store、デプロイ、バージョンアップ。
---

# iOS App Release Skill

VoiceDocs (シンプル文字起こし) をApp Storeにリリースする包括的な手順。

## 指示

### Step 1: バージョン確認とユーザー承認

```bash
# 現在のバージョン確認
grep -A1 'MARKETING_VERSION' voicedocs.xcodeproj/project.pbxproj | head -4

# 最新タグ確認
git tag --sort=-v:refname | head -5
```

**必ずユーザーに確認:**
- 新しいバージョン番号（パッチ/マイナー/メジャー）
- リリース内容（変更点のサマリー）

### Step 2: バージョン更新・コミット・タグ

```bash
# バージョン更新 (X.X.X → Y.Y.Y)
sed -i '' 's/MARKETING_VERSION = X.X.X/MARKETING_VERSION = Y.Y.Y/g' voicedocs.xcodeproj/project.pbxproj

# コミット作成
git add -A && git commit -m "chore: バージョンY.Y.Yリリース

- 変更内容1
- 変更内容2

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# タグ作成・プッシュ
git tag vY.Y.Y && git push origin main && git push origin vY.Y.Y

# GitHubリリース作成
gh release create vY.Y.Y --title "vY.Y.Y" --notes "## 変更内容
- 変更内容1
- 変更内容2"
```

### Step 3: アーカイブ作成

```bash
xcodebuild -project voicedocs.xcodeproj \
  -scheme voicedocs \
  -configuration Release \
  -archivePath ./build/voicedocs.xcarchive \
  archive
```

### Step 4: App Store Connectにアップロード

```bash
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

# アップロード実行
xcodebuild -exportArchive \
  -archivePath ./build/voicedocs.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath ./build/export \
  -allowProvisioningUpdates
```

### Step 5: Fastlaneで審査提出

```bash
source fastlane/.env.default && fastlane upload_metadata
```

**注意**: ビルドがApp Store Connectにアップロードされてから審査提出すること。

## 使用例

### 例1: パッチリリース（バグ修正）
```
User: "0.5.1のパッチリリースしたい、録音バグを修正した"
Claude: [バージョン確認 → 0.5.1に更新 → コミット → タグ → アーカイブ → アップロード → 審査提出]
```

### 例2: マイナーリリース（新機能追加）
```
User: "0.6.0リリースして、AI文字起こし精度向上を追加"
Claude: [バージョン確認 → 0.6.0に更新 → コミット → タグ → アーカイブ → アップロード → 審査提出]
```

## トラブルシューティング

### エラー: "No profiles for 'com.entaku.voicedocs' were found"
**解決方法**: Xcodeでプロファイルをダウンロード
1. Xcode → Settings → Accounts
2. Apple IDを選択
3. Download Manual Profiles

### エラー: "No Accounts with App Store Connect Access"
**解決方法**: `-allowProvisioningUpdates` フラグを追加（Step 4で既に含まれている）

### ビルドがApp Store Connectに表示されない
**解決方法**: 数分待ってから `fastlane upload_metadata` を再実行

### 環境変数が読み込まれない
**解決方法**: `fastlane/.env.default` に以下が設定されているか確認:
```
APP_STORE_CONNECT_API_KEY_KEY_ID=xxx
APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxx
APP_STORE_CONNECT_API_KEY_CONTENT=xxx
```

## クイックリファレンス

```bash
# 全手順を一気に実行（バージョンとリリース内容は事前確認済みの場合）
xcodebuild -project voicedocs.xcodeproj -scheme voicedocs -configuration Release -archivePath ./build/voicedocs.xcarchive archive && \
xcodebuild -exportArchive -archivePath ./build/voicedocs.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates && \
source fastlane/.env.default && fastlane upload_metadata

# タスク完了通知
afplay /System/Library/Sounds/Funk.aiff
```
