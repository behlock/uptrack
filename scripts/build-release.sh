#!/usr/bin/env bash
#
# Local release build — mirrors the CI pipeline for testing.
# Usage: ./scripts/build-release.sh [--notarize]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

NOTARIZE=false
if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
fi

echo "==> Generating Xcode project"
cd "$PROJECT_DIR"
xcodegen generate

echo "==> Resolving SPM dependencies"
xcodebuild -resolvePackageDependencies \
  -project uptrack.xcodeproj \
  -scheme uptrack

echo "==> Archiving (Release)"
xcodebuild archive \
  -project uptrack.xcodeproj \
  -scheme uptrack \
  -configuration Release \
  -archivePath "$BUILD_DIR/uptrack.xcarchive" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=MRU883JADA

echo "==> Exporting archive"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/uptrack.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist"

echo "==> Verifying code signing"
codesign -dv --verbose=4 "$BUILD_DIR/export/uptrack.app"
# Pre-notarization spctl assessment is expected to fail (`source=Unnotarized
# Developer ID`); don't let it abort the script under `set -e`.
spctl -a -v "$BUILD_DIR/export/uptrack.app" || true

if $NOTARIZE; then
  echo "==> Creating zip for notarization"
  ditto -c -k --keepParent "$BUILD_DIR/export/uptrack.app" "$BUILD_DIR/uptrack-notarize.zip"

  echo "==> Submitting for notarization (this may take a few minutes)"
  xcrun notarytool submit "$BUILD_DIR/uptrack-notarize.zip" \
    --keychain-profile "uptrack-notarize" \
    --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$BUILD_DIR/export/uptrack.app"
  xcrun stapler validate "$BUILD_DIR/export/uptrack.app"

  rm "$BUILD_DIR/uptrack-notarize.zip"
fi

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
RELEASE_ZIP="$BUILD_DIR/uptrack-${VERSION}.zip"

echo "==> Creating release zip"
ditto -c -k --keepParent "$BUILD_DIR/export/uptrack.app" "$RELEASE_ZIP"

echo ""
echo "Done! Release artifact: $RELEASE_ZIP"
echo ""
echo "To test: unzip and run the app, verify MediaRemote tracking works."
if ! $NOTARIZE; then
  echo ""
  echo "Note: Run with --notarize to submit for Apple notarization."
  echo "First store credentials: xcrun notarytool store-credentials uptrack-notarize"
fi
