#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
PRODUCT_NAME="拓"
EXECUTABLE_NAME="AIScreenshotApp"
APP_BUNDLE_DIR="$PROJECT_ROOT_DIR/artifacts/$PRODUCT_NAME.app"

cd "$PROJECT_ROOT_DIR"

swift build -c release --product "$EXECUTABLE_NAME"
SWIFT_BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources"
rm -f \
    "$APP_BUNDLE_DIR/Contents/Resources/Tuo.icns" \
    "$APP_BUNDLE_DIR/Contents/Resources/Brand/Tuo-AppIcon.png" \
    "$APP_BUNDLE_DIR/Contents/Resources/TaMenuBar.png"
cp "$SWIFT_BIN_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT_DIR/Resources/Ta.icns" "$APP_BUNDLE_DIR/Contents/Resources/Ta.icns"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources/Brand"
cp "$PROJECT_ROOT_DIR/Resources/Brand/Ta-AppIcon.png" "$APP_BUNDLE_DIR/Contents/Resources/Brand/Ta-AppIcon.png"
rm -rf "$APP_BUNDLE_DIR/Contents/Resources/Brand/Providers"
cp -R "$PROJECT_ROOT_DIR/Resources/Brand/Providers" "$APP_BUNDLE_DIR/Contents/Resources/Brand/Providers"

chmod 755 "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
plutil -lint "$APP_BUNDLE_DIR/Contents/Info.plist"

SIGNING_IDENTITY="${AI_SCREENSHOT_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing with stable development identity: $SIGNING_IDENTITY"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE_DIR"
else
    echo "Warning: no Apple Development identity found; using ad-hoc signing."
    echo "macOS screen-capture permission may need to be granted again after each rebuild."
    codesign --force --deep --sign - "$APP_BUNDLE_DIR"
fi

codesign --verify --deep --strict "$APP_BUNDLE_DIR"

echo "$APP_BUNDLE_DIR"
