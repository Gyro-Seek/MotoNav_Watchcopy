#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${MOTONAV_DERIVED_DATA:-$(mktemp -d /tmp/MotoNavRelease.XXXXXX)}"
OUT="$ROOT/output/ios"
mkdir -p "$OUT"
xcodebuild -workspace "$ROOT/ios/MotoNav.xcworkspace" -scheme MotoNav \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build
APP="$DERIVED/Build/Products/Release-iphoneos/MotoNav.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")
EXPECTED=$(tr -d '[:space:]' < "$ROOT/RELEASE_VERSION")
EXT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/PlugIns/MotoNavShare.appex/Info.plist")
if [[ "$VERSION" != "$EXPECTED" || "$EXT_VERSION" != "$EXPECTED" ]]; then
  echo "Version mismatch: expected=$EXPECTED app=$VERSION extension=$EXT_VERSION" >&2
  exit 1
fi
STAGE=$(mktemp -d /tmp/MotoNavPayload.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/MotoNav.app"
# Remove any local signing remnants; the recipient signs with their own account.
find "$STAGE" -name _CodeSignature -type d -prune -exec rm -rf {} +
find "$STAGE" -name embedded.mobileprovision -delete
# Plain build products can retain compiler source paths in debug symbol tables.
xcrun strip -S "$STAGE/Payload/MotoNav.app/MotoNav"
xcrun strip -S "$STAGE/Payload/MotoNav.app/PlugIns/MotoNavShare.appex/MotoNavShare"
IPA="$OUT/MotoNav-$VERSION-unsigned.ipa"
rm -f "$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
(cd "$OUT" && shasum -a 256 "$(basename "$IPA")" > SHA256SUMS.txt)
echo "$IPA"
