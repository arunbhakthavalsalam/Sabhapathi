#!/usr/bin/env bash
# Build, sign, notarize, and staple Sabhapathi.app for distribution.
#
# Requires env vars (do not commit these):
#   APPLE_ID          Apple ID email used for notarytool
#   APP_PASSWORD      App-specific password from appleid.apple.com
#   TEAM_ID           Apple Developer Team ID (default: VJ5KRG427U)
#
# Usage:
#   APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#     scripts/package_release.sh

set -euo pipefail

TEAM_ID="${TEAM_ID:-VJ5KRG427U}"
: "${APPLE_ID:?APPLE_ID env var is required}"
: "${APP_PASSWORD:?APP_PASSWORD env var is required}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Sabhapathi.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/Sabhapathi.app"
ZIP_PATH="$BUILD_DIR/Sabhapathi.zip"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
PLIST

echo "==> Archiving..."
xcodebuild \
  -project "$REPO_ROOT/SabhapathiApp.xcodeproj" \
  -scheme Sabhapathi \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting signed .app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: exported app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Zipping for notarization..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to notarization service (this can take several minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

echo "==> Stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "==> Re-zipping stapled .app..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "Done."
echo "Signed, notarized, stapled app:"
echo "  $APP_PATH"
echo "Distributable zip:"
echo "  $ZIP_PATH"
