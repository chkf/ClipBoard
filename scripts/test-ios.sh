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
for result in build/Tests.xcresult build/KeyboardMotion.xcresult; do
  if [[ -e "$result" ]]; then
    previous="$(mktemp -d "$PWD/build/previous-tests.XXXXXX")"
    mv "$result" "$previous/"
  fi
done
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcodebuild -quiet build-for-testing -project Clipboard.xcodeproj -scheme Clipboard \
  -destination "platform=iOS Simulator,id=$device" -destination-timeout 180 -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- | tee build/tests.log
xcrun simctl boot "$device" || xcrun simctl bootstatus "$device" -b
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance "${CLIPBOARD_TEST_APPEARANCE:-light}"
xcrun simctl install "$device" build/DerivedData/Build/Products/Debug-iphonesimulator/ClipboardTestHost.app
run_tests=(xcodebuild test-without-building -project Clipboard.xcodeproj -scheme Clipboard
           -destination "platform=iOS Simulator,id=$device" -destination-timeout 180 -derivedDataPath build/DerivedData
           -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
motion_test=ClipboardUITests/ClipboardUITests/testSystemKeyboardSwitchKeepsFrameSteady
test_status=0
"${run_tests[@]}" "-skip-testing:$motion_test" -retry-tests-on-failure -test-iterations 2 -resultBundlePath build/Tests.xcresult \
  | tee -a build/tests.log || test_status=$?

# Only the keyboard handoff needs screen recording. Leave the simulator free for
# pasteboard IPC and accessibility snapshots during the rest of the test suite.
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
"${run_tests[@]}" "-only-testing:$motion_test" -resultBundlePath build/KeyboardMotion.xcresult \
  | tee -a build/tests.log || test_status=$?
stop_recording
mkdir -p build/screenshots/KeyboardMotion
xcrun xcresulttool export attachments --path build/KeyboardMotion.xcresult --output-path build/screenshots/KeyboardMotion
if ! python3 scripts/check-keyboard.py motion build/screenshots/KeyboardMotion build/keyboard-motion.mov build/screenshots/KeyboardSwitch.mp4 | tee -a build/tests.log; then
  ffmpeg -v error -y -i build/keyboard-motion.mov -an -vf 'scale=360:-2,fps=12' -c:v libx264 -preset veryfast -crf 26 \
    -movflags +faststart build/screenshots/KeyboardSwitch-diagnostic.mp4
  exit 1
fi
exit "$test_status"
