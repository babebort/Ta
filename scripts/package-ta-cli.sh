#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_ROOT_DIR/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
RELEASE_DIR="${2:-$PROJECT_ROOT_DIR/artifacts/release/v$VERSION}"
ARCHIVE_NAME="Ta-CLI-$VERSION-macOS-universal.tar.gz"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
PROTOCOL_VERSION="$(sed -n 's/.*currentVersion = \([0-9][0-9]*\).*/\1/p' "$PROJECT_ROOT_DIR/Sources/TaAgentContracts/AgentEnvelope.swift" | head -n 1)"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid CLI release version: $VERSION" >&2
    exit 1
fi
if [[ -z "$PROTOCOL_VERSION" ]]; then
    echo "Unable to resolve Ta Bridge protocol version." >&2
    exit 1
fi

mkdir -p "$RELEASE_DIR"
cd "$PROJECT_ROOT_DIR"

echo "Building ta CLI $VERSION for Apple Silicon and Intel..."
swift build -c release --triple arm64-apple-macosx14.0 --product ta
swift build -c release --triple x86_64-apple-macosx14.0 --product ta

ARM64_BIN_DIR="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)"
X86_64_BIN_DIR="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ta-cli.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
PACKAGE_DIR="$STAGING_DIR/ta-cli-$VERSION"
mkdir -p "$PACKAGE_DIR/bin"

lipo -create \
    "$ARM64_BIN_DIR/ta" \
    "$X86_64_BIN_DIR/ta" \
    -output "$PACKAGE_DIR/bin/ta"
chmod 755 "$PACKAGE_DIR/bin/ta"
cp "$PROJECT_ROOT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"

MANIFEST_PATH="$PACKAGE_DIR/manifest.json"
plutil -create xml1 "$MANIFEST_PATH"
plutil -insert name -string "ta" "$MANIFEST_PATH"
plutil -insert version -string "$VERSION" "$MANIFEST_PATH"
plutil -insert bridgeProtocol -integer "$PROTOCOL_VERSION" "$MANIFEST_PATH"
plutil -insert requiresTaApp -string ">=$VERSION" "$MANIFEST_PATH"
plutil -insert minimumMacOS -string "14.0" "$MANIFEST_PATH"
plutil -insert architectures -json '["arm64","x86_64"]' "$MANIFEST_PATH"
plutil -convert json -r "$MANIFEST_PATH"

codesign --force --sign - "$PACKAGE_DIR/bin/ta"
codesign --verify --strict "$PACKAGE_DIR/bin/ta"
test "$(lipo -archs "$PACKAGE_DIR/bin/ta")" = "x86_64 arm64"

rm -f "$ARCHIVE_PATH"
COPYFILE_DISABLE=1 tar -C "$STAGING_DIR" -czf "$ARCHIVE_PATH" "ta-cli-$VERSION"
echo "$ARCHIVE_PATH"
