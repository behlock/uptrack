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
  -project PBTrack.xcodeproj \
  -scheme PBTrack

echo "==> Archiving (Release)"
xcodebuild archive \
  -project PBTrack.xcodeproj \
  -scheme PBTrack \
  -configuration Release \
  -archivePath "$BUILD_DIR/PBTrack.xcarchive" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=MRU883JADA

echo "==> Exporting archive"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/PBTrack.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist"

echo "==> Verifying code signing"
codesign -dv --verbose=4 "$BUILD_DIR/export/PBTrack.app"
spctl -a -v "$BUILD_DIR/export/PBTrack.app"

if $NOTARIZE; then
  echo "==> Creating zip for notarization"
  ditto -c -k --keepParent "$BUILD_DIR/export/PBTrack.app" "$BUILD_DIR/PBTrack-notarize.zip"

  echo "==> Submitting for notarization (this may take a few minutes)"
  xcrun notarytool submit "$BUILD_DIR/PBTrack-notarize.zip" \
    --keychain-profile "pbtrack-notarize" \
    --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$BUILD_DIR/export/PBTrack.app"
  xcrun stapler validate "$BUILD_DIR/export/PBTrack.app"

  rm "$BUILD_DIR/PBTrack-notarize.zip"
fi

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
RELEASE_ZIP="$BUILD_DIR/PBTrack-${VERSION}.zip"

echo "==> Creating release zip"
ditto -c -k --keepParent "$BUILD_DIR/export/PBTrack.app" "$RELEASE_ZIP"

echo ""
echo "Done! Release artifact: $RELEASE_ZIP"
echo ""
echo "To test: unzip and run the app, verify MediaRemote tracking works."
if ! $NOTARIZE; then
  echo ""
  echo "Note: Run with --notarize to submit for Apple notarization."
  echo "First store credentials: xcrun notarytool store-credentials pbtrack-notarize"
fi
