#!/bin/bash
set -euo pipefail

device="$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"]
requested = os.environ.get("CLIPBOARD_TEST_DEVICE", "iPhone 17")
versions = sorted((key for key in devices if ".iOS-26-" in key),
                  key=lambda key: tuple(int(n) for n in key.split(".iOS-")[-1].split("-")), reverse=True)
for version in versions:
    phones = [d for d in devices[version] if d["name"].startswith("iPhone") and d["isAvailable"]]
    selected = next((d for d in phones if d["name"] == requested), None)
    if selected:
        print(selected["udid"])
        break
else:
    raise SystemExit(f"{requested} running iOS 26 is required")
')"
mkdir -p build
if [[ -e build/Tests.xcresult ]]; then
  previous="$(mktemp -d "$PWD/build/previous-tests.XXXXXX")"
  mv build/Tests.xcresult "$previous/"
fi
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcodebuild -quiet build-for-testing -project Clipboard.xcodeproj -scheme Clipboard \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- | tee build/tests.log
xcrun simctl boot "$device" || xcrun simctl bootstatus "$device" -b
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance "${CLIPBOARD_TEST_APPEARANCE:-light}"
xcrun simctl install "$device" build/DerivedData/Build/Products/Debug-iphonesimulator/ClipboardTestHost.app
command -v ffmpeg >/dev/null || brew install ffmpeg
xcrun simctl io "$device" recordVideo --codec=h264 --force build/keyboard-motion.mov >build/recording.log 2>&1 &
recorder=$!
stop_recording() {
  if [[ -n "$recorder" ]]; then
    kill -INT "$recorder" 2>/dev/null || true
    wait "$recorder" || true
    recorder=''
  fi
}
trap stop_recording EXIT
xcodebuild test-without-building -project Clipboard.xcodeproj -scheme Clipboard \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO -resultBundlePath build/Tests.xcresult \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- | tee -a build/tests.log
stop_recording
python3 scripts/check-keyboard-motion.py build/keyboard-motion.mov | tee -a build/tests.log
