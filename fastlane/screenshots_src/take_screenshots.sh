#!/bin/bash
#
# App Store 用スクリーンショットを生成する。
#
#   1. 対象シミュレータを綺麗な状態から起動する
#   2. アプリをビルドしてインストールし、一度起動して Core Data ストアを作る
#   3. seed_data.py で実物らしい日本語データを投入する
#   4. ステータスバーを 9:41 / 満充電 / 電波フルに固定する
#   5. ScreenshotUITests を SCREENSHOT_MODE=1 で走らせて撮影する
#   6. .xcresult から PNG を取り出して fastlane/screenshots/ja/ に置く
#
# 使い方:
#   ./fastlane/screenshots_src/take_screenshots.sh [device-name]
#
# 既定のデバイスは 6.9インチ相当（1320x2868）の iPhone 16 Pro Max。
# App Store Connect の iPhone スクリーンショット枠に合わせている。
#
# 注意:
# - このスクリプトはアップロードしない。fastlane deliver / upload_screenshots は呼ばない
# - `-parallel-testing-enabled NO` は必須。クローン端末だと UI テストランナーが
#   `Failed to launch app` で起動できない（issue #31）。実機デバイス上で直接走らせる
# - テスト実行が停滞したら simctl shutdown all してから再実行する（issue #31）
# - AIノートの「生成後」の画面はシミュレータでは撮れない。isAvailable は true を返すが
#   実際の生成が返ってこないため、その1枚だけは実機で撮る必要がある
#
set -euo pipefail

DEVICE_NAME="${1:-iPhone 16 Pro Max}"
BUNDLE_ID="com.entaku.voicedocs"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$REPO_ROOT/fastlane/screenshots_src"
OUT_DIR="$REPO_ROOT/fastlane/screenshots/ja"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> 対象デバイス: $DEVICE_NAME"
UDID=$(xcrun simctl list devices available -j \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for runtime, devices in d.items():
    for dev in devices:
        if dev['name'] == '''$DEVICE_NAME''':
            print(dev['udid']); raise SystemExit
raise SystemExit('デバイスが見つかりません: $DEVICE_NAME')
")
echo "    UDID: $UDID"

echo "==> シミュレータをリセットして起動"
xcrun simctl shutdown all >/dev/null 2>&1 || true
sleep 3
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "==> ビルド"
xcodebuild -workspace "$REPO_ROOT/voicedocs.xcodeproj/project.xcworkspace" \
  -scheme voicedocs -configuration Debug \
  -destination "id=$UDID" -skipMacroValidation \
  build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)" || true

APP=$(find ~/Library/Developer/Xcode/DerivedData/voicedocs-*/Build/Products/Debug-iphonesimulator \
  -maxdepth 1 -name "voicedocs.app" | head -1)
if [ -z "$APP" ]; then
  echo "voicedocs.app が見つかりません" >&2
  exit 1
fi

echo "==> インストールして一度起動（Core Data ストアを作る）"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep 8
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> テストデータを投入"
python3 "$SRC_DIR/seed_data.py" "$UDID"

echo "==> ステータスバーを固定"
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

echo "==> 撮影（オンデバイス生成を待つので時間がかかる）"
RESULT_BUNDLE="$WORK_DIR/screenshots.xcresult"
TEST_RUNNER_SCREENSHOT_MODE=1 xcodebuild \
  -workspace "$REPO_ROOT/voicedocs.xcodeproj/project.xcworkspace" \
  -scheme voicedocs -configuration Debug \
  -destination "id=$UDID" -skipMacroValidation \
  -only-testing:voicedocsUITests/ScreenshotUITests \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" \
  test 2>&1 | grep -E "(Test case|TEST SUCCEEDED|TEST FAILED|error:)" || true

echo "==> PNG を取り出す"
mkdir -p "$OUT_DIR"
ATT_DIR="$WORK_DIR/attachments"
mkdir -p "$ATT_DIR"
xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path "$ATT_DIR" >/dev/null

python3 - "$ATT_DIR" "$OUT_DIR" <<'PY'
import json, os, shutil, sys
att_dir, out_dir = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(att_dir, "manifest.json")))
count = 0
for entry in manifest:
    for a in entry.get("attachments", []):
        name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        base = name.split("_0_")[0]
        if not base.endswith(".png"):
            base += ".png"
        shutil.copy(os.path.join(att_dir, a["exportedFileName"]),
                    os.path.join(out_dir, base))
        count += 1
print(f"    {count} 枚を {out_dir} に出力")
PY

echo "==> 出力"
for f in "$OUT_DIR"/*.png; do
  printf "    %s  " "$(basename "$f")"
  sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | tail -2 | tr -d '\n' | sed 's/  */ /g'
  echo
done

echo
echo "完了。アップロードはしていない。反映する場合は人間が fastlane deliver を判断すること。"
