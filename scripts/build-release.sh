#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
BUILD_DIR="$ROOT/.build-release"
ARCHIVE_PATH="$BUILD_DIR/SystemPulse.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$ROOT/dist"
APP_NAME="System Pulse.app"
DMG_NAME="System-Pulse-${VERSION}.dmg"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$DIST_DIR"

cd "$ROOT"
xcodegen generate
xcodebuild \
  -project SystemPulse.xcodeproj \
  -scheme SystemPulse \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION=1 \
  clean build

ditto "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME" "$EXPORT_DIR/$APP_NAME"
codesign --force --deep --sign - "$EXPORT_DIR/$APP_NAME"
codesign --verify --deep --strict "$EXPORT_DIR/$APP_NAME"

mkdir -p "$BUILD_DIR/dmg"
ditto "$EXPORT_DIR/$APP_NAME" "$BUILD_DIR/dmg/$APP_NAME"
ln -s /Applications "$BUILD_DIR/dmg/Applications"

hdiutil create \
  -volname "System Pulse ${VERSION}" \
  -srcfolder "$BUILD_DIR/dmg" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME"

hdiutil verify "$DIST_DIR/$DMG_NAME"
shasum -a 256 "$DIST_DIR/$DMG_NAME" > "$DIST_DIR/$DMG_NAME.sha256"

echo "Created $DIST_DIR/$DMG_NAME"
