#!/bin/bash
set -euo pipefail

version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a numeric release version"; exit 1; }
output="$PWD/build"
mkdir -p "$output/release"
work="$(mktemp -d "$output/package.XXXXXX")"

xcodebuild archive -project Clipboard.xcodeproj -scheme Clipboard -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$work/Clipboard.xcarchive" \
  -derivedDataPath "$output/DerivedData" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | tee "$output/archive.log"
for mode in local resign; do
  directory="$work/$mode"
  mkdir -p "$directory/Payload"
  app="$directory/Payload/Clipboard.app"
  keyboard="$app/PlugIns/ClipboardKeyboard.appex"
  entitlements="$directory/entitlements.plist"
  asset="Clipboard-$version-$mode.ipa"
  ditto "$work/Clipboard.xcarchive/Products/Applications/Clipboard.app" "$app"
  /usr/bin/plutil -create xml1 "$entitlements"
  if [[ "$mode" == local ]]; then
    for bundle in "$app" "$keyboard"; do
      /usr/libexec/PlistBuddy -c 'Add :ClipboardPrivateHistory bool true' "$bundle/Info.plist"
    done
  else
    group="$(/usr/libexec/PlistBuddy -c 'Print :ClipboardAppGroup' "$app/Info.plist")"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' "$entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups:0 string $group" "$entitlements"
  fi
  while IFS= read -r -d '' library; do
    codesign --force --sign - --timestamp=none "$library"
  done < <(find "$app" -depth \( -name '*.dylib' -o -name '*.framework' \) -print0)
  for bundle in "$keyboard" "$app"; do
    codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$entitlements" "$bundle"
  done
  ditto -ck --keepParent "$directory/Payload" "$output/release/$asset"
  ditto -xk "$output/release/$asset" "$directory/verify"
  python3 scripts/verify-ipa.py "$directory/verify/Payload/Clipboard.app" "$version" "$mode"
  (cd "$output/release" && shasum -a 256 "$asset" > "$asset.sha256" && shasum -a 256 -c "$asset.sha256")
done
