#!/bin/bash
# GitHub Actions self-hosted runner（.github/workflows/ios-ci.yml）から呼ばれる iOS CI 本体。
# ローカルでも同じコマンドで再現できる:
#   DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer scripts/ios-ci.sh
#
# - シミュレータは他リポジトリの runner と取り合わないよう専用の CI-voicedocs を使う
# - DerivedData は作業ディレクトリ配下（build/ci/DerivedData）に置き、他リポジトリと共有しない
# - Prod.xcconfig（gitignore・AdMob ID 入り）が無ければ空値のダミーを生成する。空値は AdMobKeys が広告無効として扱う
set -euo pipefail

cd "$(dirname "$0")/.."

WORKSPACE="voicedocs.xcodeproj/project.xcworkspace"
SIM_NAME="CI-voicedocs"
SIM_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
SIM_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
OUT_DIR="build/ci"
DERIVED_DATA="$OUT_DIR/DerivedData"
RESULT_BUNDLE="$OUT_DIR/TestResults.xcresult"

mkdir -p "$OUT_DIR"
rm -rf "$RESULT_BUNDLE"

echo "::group::Environment"
xcodebuild -version
echo "::endgroup::"

# 旧 Xcode Cloud（ci_scripts/ci_post_clone.sh）から移植: マクロの fingerprint 検証を無効化
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

if [ ! -f voicedocs/Prod.xcconfig ]; then
  # テスト側（AdMobConfigurationTests）に「ダミーで生成した」ことを伝える。TEST_RUNNER_ 接頭辞はテストプロセスへ渡る
  export TEST_RUNNER_VOICEDOCS_CI_DUMMY_XCCONFIG=1
  echo "Prod.xcconfig が無いので CI 用ダミー（空値）を生成"
  cat > voicedocs/Prod.xcconfig <<'XCCONFIG'
// CI 用ダミー（scripts/ios-ci.sh が生成）。空値は AdMobKeys.sanitize で広告無効として扱われる
ADMOB_KEY =
ADMOB_BANNER_KEY =
ADMOB_APP_OPEN_KEY =
XCCONFIG
fi

echo "::group::Simulator ($SIM_NAME)"
SIM_UDID=$(xcrun simctl list devices -j | /usr/bin/python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices'].get('$SIM_RUNTIME', [])
print(next((d['udid'] for d in devices if d['name'] == '$SIM_NAME' and d['isAvailable']), ''))
")
if [ -z "$SIM_UDID" ]; then
  SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$SIM_DEVICE_TYPE" "$SIM_RUNTIME")
  echo "created $SIM_NAME ($SIM_UDID)"
fi
# 高負荷時に初回テストが接続タイムアウトしないよう、boot 完了まで待ってから test する
xcrun simctl bootstatus "$SIM_UDID" -b
echo "::endgroup::"

echo "::group::Build (voicedocs / voicedocsDevelop)"
for SCHEME in voicedocs voicedocsDevelop; do
  xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED_DATA" \
    -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
done
echo "::endgroup::"

echo "::group::Unit tests"
# voicedocsUITests は Failed to launch app で完走しない既知の問題（issue #31）のため対象外
xcodebuild -workspace "$WORKSPACE" -scheme voicedocs -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:voicedocsTests test
echo "::endgroup::"
