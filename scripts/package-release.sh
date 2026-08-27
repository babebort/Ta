#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
PRODUCT_NAME="拓"
EXECUTABLE_NAME="AIScreenshotApp"
INFO_PLIST="$PROJECT_ROOT_DIR/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
RELEASE_DIR="$PROJECT_ROOT_DIR/artifacts/release/v$VERSION"
APP_BUNDLE_DIR="$RELEASE_DIR/$PRODUCT_NAME.app"
DMG_PATH="$RELEASE_DIR/Ta-$VERSION-macOS-universal.dmg"
ZIP_PATH="$RELEASE_DIR/Ta-$VERSION-macOS-universal.zip"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
CLI_ARCHIVE_PATH="$RELEASE_DIR/Ta-CLI-$VERSION-macOS-universal.tar.gz"
SKILL_ARCHIVE_PATH="$RELEASE_DIR/Ta-Agent-Skill-$VERSION.zip"
DSH_ARCHIVE_PATH="$RELEASE_DIR/dsh-ta-$VERSION.tgz"
INSTALLER_PATH="$RELEASE_DIR/install.sh"

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid release version: $VERSION" >&2
    exit 1
fi
if [[ "$VERSION" != "$PLIST_VERSION" ]]; then
    echo "Version mismatch: requested $VERSION, Info.plist contains $PLIST_VERSION" >&2
    exit 1
fi

cd "$PROJECT_ROOT_DIR"

echo "Building Ta $VERSION for Apple Silicon and Intel..."
swift build -c release --triple arm64-apple-macosx14.0 --product "$EXECUTABLE_NAME"
swift build -c release --triple x86_64-apple-macosx14.0 --product "$EXECUTABLE_NAME"

ARM64_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)"
X86_64_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources/Brand"

lipo -create \
    "$ARM64_BIN_DIR/$EXECUTABLE_NAME" \
    "$X86_64_BIN_DIR/$EXECUTABLE_NAME" \
    -output "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT_DIR/Resources/Ta.icns" "$APP_BUNDLE_DIR/Contents/Resources/Ta.icns"
cp "$PROJECT_ROOT_DIR/Resources/Brand/Ta-AppIcon.png" \
    "$APP_BUNDLE_DIR/Contents/Resources/Brand/Ta-AppIcon.png"
cp -R "$PROJECT_ROOT_DIR/Resources/Brand/Providers" \
    "$APP_BUNDLE_DIR/Contents/Resources/Brand/Providers"
chmod 755 "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"

plutil -lint "$APP_BUNDLE_DIR/Contents/Info.plist"

SIGNING_IDENTITY="${TA_RELEASE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing with: $SIGNING_IDENTITY"
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE_DIR"
else
    echo "Warning: no signing identity found; using ad-hoc signing."
    codesign --force --deep --sign - "$APP_BUNDLE_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_DIR"
test "$(lipo -archs "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME")" = "x86_64 arm64"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ta-release.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_BUNDLE_DIR" "$STAGING_DIR/$PRODUCT_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "拓 Ta" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE_DIR" "$ZIP_PATH"

"$PROJECT_ROOT_DIR/scripts/package-ta-cli.sh" "$VERSION" "$RELEASE_DIR"
"$PROJECT_ROOT_DIR/scripts/package-ta-skill.sh" "$VERSION" "$RELEASE_DIR"
"$PROJECT_ROOT_DIR/scripts/package-dsh-ta.sh" "$VERSION" "$RELEASE_DIR"
cp "$PROJECT_ROOT_DIR/scripts/install.sh" "$INSTALLER_PATH"
chmod 755 "$INSTALLER_PATH"

(
    cd "$RELEASE_DIR"
    shasum -a 256 \
        "${DMG_PATH:t}" \
        "${ZIP_PATH:t}" \
        "${CLI_ARCHIVE_PATH:t}" \
        "${SKILL_ARCHIVE_PATH:t}" \
        "${DSH_ARCHIVE_PATH:t}" \
        "${INSTALLER_PATH:t}" \
        > "${CHECKSUM_PATH:t}"
)

echo "Release artifacts:"
ls -lh \
    "$DMG_PATH" \
    "$ZIP_PATH" \
    "$CLI_ARCHIVE_PATH" \
    "$SKILL_ARCHIVE_PATH" \
    "$DSH_ARCHIVE_PATH" \
    "$INSTALLER_PATH" \
    "$CHECKSUM_PATH"
cat "$CHECKSUM_PATH"
