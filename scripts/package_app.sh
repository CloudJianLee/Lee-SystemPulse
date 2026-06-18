#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Lee-SystemPulse"
PRODUCT_NAME="lee-system-pulse"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_RESOURCES_DIR="$CONTENTS_DIR/Resources"
VERSION_FILE="$ROOT_DIR/Config/Version.env"
PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
ARCHIVE=false
SKIP_TESTS=false
INSTALL=false
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

usage() {
  cat <<EOF
Usage: ./Scripts/package_app.sh [options]

Options:
  --archive      Also create a versioned DMG and SHA-256 checksum.
  --install      Install the app to /Applications after packaging.
  --skip-tests   Skip the Swift test suite.
  -h, --help     Show this help.

Environment:
  SIGN_IDENTITY  codesign identity. Defaults to "-" (ad-hoc signing).
EOF
}

while (($# > 0)); do
  case "$1" in
    --archive)
      ARCHIVE=true
      ;;
    --install)
      INSTALL=true
      ;;
    --skip-tests)
      SKIP_TESTS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command in swift plutil codesign lipo hdiutil shasum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

if [[ ! -f "$VERSION_FILE" || ! -f "$PLIST_TEMPLATE" || ! -f "$ICON_FILE" ]]; then
  echo "Missing version configuration, Info.plist template, or app icon." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_FILE"

: "${MARKETING_VERSION:?MARKETING_VERSION is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
: "${MINIMUM_MACOS_VERSION:?MINIMUM_MACOS_VERSION is required}"

cd "$ROOT_DIR"

if [[ "$SKIP_TESTS" == false ]]; then
  swift test
fi

UNIVERSAL=false
XCBUILD_PATH="/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"
if [[ -x "$XCBUILD_PATH" ]]; then
  swift build \
    -c release \
    --product "$PRODUCT_NAME" \
    --arch arm64 \
    --arch x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  BINARY_PATH="$BIN_DIR/$PRODUCT_NAME"
  ARCHITECTURES="$(lipo -archs "$BINARY_PATH")"
  if [[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]; then
    UNIVERSAL=true
    ARCH_LABEL="universal"
  fi
fi

if [[ "$UNIVERSAL" == false ]]; then
  swift build \
    -c release \
    --product "$PRODUCT_NAME"
  BIN_DIR="$(swift build -c release --show-bin-path)"
  BINARY_PATH="$BIN_DIR/$PRODUCT_NAME"
  MACHINE_ARCH="$(uname -m)"
  ARCH_LABEL="$MACHINE_ARCH"
  ARCHITECTURES="$MACHINE_ARCH"
fi

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Release binary not found: $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
cp "$ICON_FILE" "$APP_RESOURCES_DIR/AppIcon.icns"

plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$MINIMUM_MACOS_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -lint "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Packaged: $APP_DIR"
echo "Version:  $MARKETING_VERSION ($BUILD_NUMBER)"
echo "Archs:    $ARCHITECTURES"

if [[ "$ARCHIVE" == true ]]; then
  DMG_PATH="$DIST_DIR/$APP_NAME-v$MARKETING_VERSION-macos-${ARCH_LABEL}.dmg"
  CHECKSUM_PATH="$DMG_PATH.sha256"
  DMG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lee-system-pulse-dmg.XXXXXX")"

  cleanup() {
    rm -rf "$DMG_ROOT"
  }
  trap cleanup EXIT

  cp -R "$APP_DIR" "$DMG_ROOT/"
  ln -s /Applications "$DMG_ROOT/Applications"

  rm -f "$DMG_PATH" "$CHECKSUM_PATH"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  (
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
  )

  echo "Disk image: $DMG_PATH"
  echo "Checksum: $CHECKSUM_PATH"
fi

if [[ "$INSTALL" == true ]]; then
  INSTALL_DEST="/Applications/$APP_NAME.app"
  if [[ -d "$INSTALL_DEST" ]]; then
    echo "Removing existing app at $INSTALL_DEST"
    rm -rf "$INSTALL_DEST"
  fi
  cp -R "$APP_DIR" "/Applications/"
  echo "Installed: $INSTALL_DEST"
fi
