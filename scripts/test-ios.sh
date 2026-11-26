#!/bin/bash
set -euo pipefail

device="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
versions = sorted((key for key in devices if ".iOS-26-" in key),
                  key=lambda key: tuple(int(n) for n in key.split(".iOS-")[-1].split("-")), reverse=True)
for version in versions:
    phones = [d for d in devices[version] if d["name"].startswith("iPhone") and d["isAvailable"]]
    if phones:
        print(next((d for d in phones if d["name"] == "iPhone 17"), phones[0])["udid"])
        break
else:
    raise SystemExit("An iPhone simulator running iOS 26 is required")
')"
mkdir -p build
if [[ -e build/Tests.xcresult ]]; then
  previous="$(mktemp -d "$PWD/build/previous-tests.XXXXXX")"
  mv build/Tests.xcresult "$previous/"
fi
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl boot "$device" || xcrun simctl bootstatus "$device" -b
xcodebuild -quiet build-for-testing -project Clipboard.xcodeproj -scheme Clipboard \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- | tee build/tests.log
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance "${CLIPBOARD_TEST_APPEARANCE:-light}"
xcrun simctl install "$device" build/DerivedData/Build/Products/Debug-iphonesimulator/ClipboardTestHost.app
xcodebuild test-without-building -project Clipboard.xcodeproj -scheme Clipboard \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO -resultBundlePath build/Tests.xcresult \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- | tee -a build/tests.log
