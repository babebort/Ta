#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_ROOT_DIR/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
RELEASE_DIR="${2:-$PROJECT_ROOT_DIR/artifacts/release/v$VERSION}"
PACKAGE_DIR="$PROJECT_ROOT_DIR/Integrations/DeepSeekHarness/dsh-ta"
NODE_BIN="${TA_NODE_BIN:-$(command -v node || true)}"

if [[ -z "$NODE_BIN" ]]; then
    echo "Node.js 22.19.0 or newer is required to package dsh-ta." >&2
    exit 1
fi
if ! "$NODE_BIN" -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit((a===22&&b>=19)||a>=24?0:1)'; then
    echo "Node.js 22.19.0 or newer is required; found $($NODE_BIN -p 'process.versions.node')." >&2
    exit 1
fi

NODE_DIR="${NODE_BIN:A:h}"
NPM_BIN="${TA_NPM_BIN:-$NODE_DIR/npm}"
if [[ ! -x "$NPM_BIN" ]]; then
    NPM_BIN="$(command -v npm || true)"
fi
if [[ -z "$NPM_BIN" ]]; then
    echo "npm is required to package dsh-ta." >&2
    exit 1
fi

PACKAGE_VERSION="$(cd "$PACKAGE_DIR" && "$NODE_BIN" -p 'require("./package.json").version')"
if [[ "$VERSION" != "$PACKAGE_VERSION" ]]; then
    echo "Version mismatch: Ta is $VERSION but dsh-ta is $PACKAGE_VERSION." >&2
    exit 1
fi

mkdir -p "$RELEASE_DIR"
cd "$PACKAGE_DIR"
echo "Testing and packaging dsh-ta $VERSION..."
PATH="$NODE_DIR:$PATH" "$NPM_BIN" ci
PATH="$NODE_DIR:$PATH" "$NPM_BIN" test
rm -f "$RELEASE_DIR/dsh-ta-$VERSION.tgz"
PATH="$NODE_DIR:$PATH" "$NPM_BIN" pack --pack-destination "$RELEASE_DIR"
test -f "$RELEASE_DIR/dsh-ta-$VERSION.tgz"
echo "$RELEASE_DIR/dsh-ta-$VERSION.tgz"
