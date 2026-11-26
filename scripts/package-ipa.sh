#!/bin/bash
set -euo pipefail

version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a numeric release version"; exit 1; }
output="$PWD/build"
mkdir -p "$output/release"
work="$(mktemp -d "$output/package.XXXXXX")"
app="$work/Payload/Clipboard.app"
extension="$app/PlugIns/ClipboardKeyboard.appex"
asset="Clipboard-$version-resign.ipa"
mkdir -p "$work/Payload"

xcodebuild archive -project Clipboard.xcodeproj -scheme Clipboard -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$work/Clipboard.xcarchive" \
  -derivedDataPath "$output/DerivedData" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$output/archive.log"
ditto "$work/Clipboard.xcarchive/Products/Applications/Clipboard.app" "$app"

group="$(/usr/libexec/PlistBuddy -c 'Print :ClipboardAppGroup' "$app/Info.plist")"
/usr/bin/plutil -create xml1 "$work/entitlements.plist"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' "$work/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $group" "$work/entitlements.plist"
while IFS= read -r -d '' library; do
  codesign --force --sign - --timestamp=none "$library"
done < <(find "$app" -depth \( -name '*.dylib' -o -name '*.framework' \) -print0)
for bundle in "$extension" "$app"; do
  codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "$work/entitlements.plist" "$bundle"
done
ditto -ck --keepParent "$work/Payload" "$output/release/$asset"

# Inspect the extracted deliverable, including both actual signatures.
ditto -xk "$output/release/$asset" "$work/verify"
python3 scripts/verify-ipa.py "$work/verify/Payload/Clipboard.app" "$version"
(cd "$output/release" && shasum -a 256 "$asset" > "$asset.sha256" && shasum -a 256 -c "$asset.sha256")
