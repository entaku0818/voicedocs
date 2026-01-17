# iOS App Release Skill

## Overview
VoiceDocs (シンプル文字起こし) をApp Storeにリリースする手順。

## Prerequisites
- Xcode がインストールされていること
- App Store Connect API Key が設定されていること（fastlane/.env.default）
- Provisioning Profile がダウンロードされていること

## Release Steps

### Step 1: バージョン確認・ユーザー確認
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

### Step 3: アーカイブ作成
```bash
xcodebuild -project voicedocs.xcodeproj -scheme voicedocs -configuration Release -archivePath ./build/voicedocs.xcarchive archive
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

# アップロード
xcodebuild -exportArchive -archivePath ./build/voicedocs.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates
```

### Step 5: Fastlaneで審査提出
```bash
source fastlane/.env.default && fastlane upload_metadata
```

## Environment Variables (fastlane/.env.default)
```
APP_STORE_CONNECT_API_KEY_KEY_ID=xxx
APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxx
APP_STORE_CONNECT_API_KEY_CONTENT=xxx
```

## Troubleshooting

### "No profiles for 'com.entaku.voicedocs' were found"
→ Xcodeでプロファイルをダウンロード:
1. Xcode → Settings → Accounts
2. Apple IDを選択
3. Download Manual Profiles

### "No Accounts with App Store Connect Access"
→ `-allowProvisioningUpdates` フラグを追加

### ビルドがApp Store Connectに表示されない
→ 数分待ってからfastlane upload_metadataを再実行

## Quick Reference
```bash
# 全手順を一気に実行（バージョンとリリース内容は事前に確認済みの場合）
xcodebuild -project voicedocs.xcodeproj -scheme voicedocs -configuration Release -archivePath ./build/voicedocs.xcarchive archive && \
xcodebuild -exportArchive -archivePath ./build/voicedocs.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates && \
source fastlane/.env.default && fastlane upload_metadata
```
