#!/bin/zsh
# Captures the App Store screenshot set (OffRecordUITests/ScreenshotTests) on a 6.9" iPhone
# and a 13" iPad, in light and dark appearance, into AppStore/screenshots/<device>/<appearance>/.
#
#   AppStore/capture-screenshots.sh [iphone|ipad ...]
#
# Needs the iOS and watchOS simulator runtimes (the OffRecord scheme embeds the watch app).
# Regenerate the seeded photos first with `node AppStore/seed-media/generate-illustrations.mjs`
# if the scenes change.

set -euo pipefail
cd "${0:A:h}/.."

DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/offrecord-screenshots-dd}"
WORK="${TMPDIR:-/tmp}/offrecord-screenshots-work"
OUT="AppStore/screenshots"
if (( $# )); then DEVICES=("$@"); else DEVICES=(iphone ipad); fi

typeset -A DEVICE_NAME DEVICE_TYPE
DEVICE_NAME[iphone]="OffRecord Shots 17 Pro Max"
DEVICE_TYPE[iphone]="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
DEVICE_NAME[ipad]="OffRecord Shots iPad Pro 13"
DEVICE_TYPE[ipad]="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
typeset -A FOLDER
FOLDER[iphone]="iPhone_69"
FOLDER[ipad]="iPad_13"

runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]["identifier"])')

device_id() {
  local name=$1 type=$2
  local id
  id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name:
            print(d["udid"]); sys.exit()' "$name")
  if [[ -z $id ]]; then
    id=$(xcrun simctl create "$name" "$type" "$runtime")
  fi
  echo "$id"
}

rm -rf "$WORK"
mkdir -p "$WORK"

first_id=$(device_id "${DEVICE_NAME[${DEVICES[1]}]}" "${DEVICE_TYPE[${DEVICES[1]}]}")
echo "Building for testing…"
xcodebuild build-for-testing \
  -scheme OffRecord \
  -destination "id=$first_id" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO \
  -quiet

for device in $DEVICES; do
  id=$(device_id "${DEVICE_NAME[$device]}" "${DEVICE_TYPE[$device]}")
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override \
    --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState charged --batteryLevel 100

  for appearance in light dark; do
    echo "Capturing $device / $appearance…"
    xcrun simctl ui "$id" appearance "$appearance"
    bundle="$WORK/$device-$appearance.xcresult"
    xcodebuild test-without-building \
      -scheme OffRecord \
      -destination "id=$id" \
      -derivedDataPath "$DERIVED_DATA" \
      -only-testing:OffRecordUITests/ScreenshotTests \
      -parallel-testing-enabled NO \
      -resultBundlePath "$bundle" \
      -quiet || echo "Some screenshot tests failed on $device/$appearance; exporting what was captured."

    export_dir="$WORK/$device-$appearance"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$export_dir" >/dev/null
    dest="$OUT/${FOLDER[$device]}/$appearance"
    rm -rf "$dest"
    mkdir -p "$dest"
    python3 - "$export_dir" "$dest" <<'PY'
import json, os, re, shutil, sys
src, dest = sys.argv[1:]
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for attachment in test.get("attachments", []):
        # Keep only the named screenshots ("01_Today_0_<uuid>.png" -> "01_Today.png"),
        # not the debug attachments XCTest adds to failures.
        match = re.match(r"^(\d{2}b?_[A-Za-z]+)", attachment.get("suggestedHumanReadableName", ""))
        if match:
            shutil.copy(os.path.join(src, attachment["exportedFileName"]), os.path.join(dest, match.group(1) + ".png"))
PY
    rm -rf "$bundle" "$export_dir"
  done
  xcrun simctl status_bar "$id" clear
done

rm -rf "$DERIVED_DATA/Logs" "$WORK"
echo "Screenshots written to $OUT"
