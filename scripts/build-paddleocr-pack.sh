#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
SOURCE_DIR="$PROJECT_ROOT_DIR/ocr-packs/paddleocr"
BUILD_DIR="$PROJECT_ROOT_DIR/.build/paddleocr-pack-portable"
DOWNLOAD_DIR="$PROJECT_ROOT_DIR/.build/downloads"
MODEL_CACHE_DIR="${PADDLEOCR_MODEL_CACHE_DIR:-$HOME/.paddlex/official_models}"
PACK_NAME="PaddleOCR-Pack-arm64-1.1.0"
PACK_DIR="$BUILD_DIR/$PACK_NAME"
RUNTIME_DIR="$PACK_DIR/runtime"
ARTIFACT_DIR="$PROJECT_ROOT_DIR/artifacts/ocr-packs"
ARCHIVE_PATH="$ARTIFACT_DIR/$PACK_NAME.zip"

PYTHON_ARCHIVE_NAME="cpython-3.12.14+20260814-aarch64-apple-darwin-install_only_stripped.tar.gz"
PYTHON_ARCHIVE_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260814/cpython-3.12.14%2B20260814-aarch64-apple-darwin-install_only_stripped.tar.gz"
PYTHON_ARCHIVE_SHA256="dd5b76ab11451a4a4367c17c61d944dded56b425396b07f102922a7ebef7d55f"
PYTHON_ARCHIVE="$DOWNLOAD_DIR/$PYTHON_ARCHIVE_NAME"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This builder currently supports Apple Silicon (arm64) only." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$DOWNLOAD_DIR" "$ARTIFACT_DIR"
if [[ ! -f "$PYTHON_ARCHIVE" ]] || [[ "$(shasum -a 256 "$PYTHON_ARCHIVE" | awk '{print $1}')" != "$PYTHON_ARCHIVE_SHA256" ]]; then
    curl -L -C - --fail --retry 3 -o "$PYTHON_ARCHIVE" "$PYTHON_ARCHIVE_URL"
fi
if [[ "$(shasum -a 256 "$PYTHON_ARCHIVE" | awk '{print $1}')" != "$PYTHON_ARCHIVE_SHA256" ]]; then
    echo "Standalone Python checksum mismatch." >&2
    exit 1
fi

rm -rf "$PACK_DIR" "$BUILD_DIR/python"
mkdir -p "$PACK_DIR/bin" "$PACK_DIR/adapter" "$PACK_DIR/models"
tar -xzf "$PYTHON_ARCHIVE" -C "$BUILD_DIR"
mv "$BUILD_DIR/python" "$RUNTIME_DIR"

"$RUNTIME_DIR/bin/python3" -m pip install --upgrade pip
"$RUNTIME_DIR/bin/python3" -m pip install -r "$SOURCE_DIR/requirements-lock.txt"

"$RUNTIME_DIR/bin/python3" "$SOURCE_DIR/prefetch_models.py" \
    --source "$MODEL_CACHE_DIR" \
    --destination "$PACK_DIR/models"
cp "$SOURCE_DIR/adapter.py" "$PACK_DIR/adapter/adapter.py"

clang \
    -arch arm64 \
    -mmacosx-version-min=14.0 \
    -O2 \
    "$SOURCE_DIR/launcher.c" \
    -o "$PACK_DIR/bin/paddleocr-adapter"
chmod 755 "$PACK_DIR/bin/paddleocr-adapter"
codesign --force --sign - "$PACK_DIR/bin/paddleocr-adapter"
codesign --verify --strict "$PACK_DIR/bin/paddleocr-adapter"

SITE_PACKAGES="$RUNTIME_DIR/lib/python3.12/site-packages"
find "$RUNTIME_DIR" -name '*.pyc' -delete
find "$RUNTIME_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$SITE_PACKAGES" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} +
rm -rf "$RUNTIME_DIR/share/doc" "$RUNTIME_DIR/share/man"

EXECUTABLE_SHA256="$(shasum -a 256 "$PACK_DIR/bin/paddleocr-adapter" | awk '{print $1}')"
sed \
    -e "s|__EXECUTABLE_SHA256__|$EXECUTABLE_SHA256|g" \
    "$SOURCE_DIR/manifest-template.json" > "$PACK_DIR/manifest.json"

"$RUNTIME_DIR/bin/python3" -m pip freeze | sort > "$PACK_DIR/SBOM-pip-freeze.txt"
"$RUNTIME_DIR/bin/python3" "$SOURCE_DIR/generate_inventory.py" > "$PACK_DIR/THIRD-PARTY-INVENTORY.json"
cp "$PROJECT_ROOT_DIR/docs/ocr-enhancement-pack-spec.md" "$PACK_DIR/PACK-PROTOCOL.md"
cp "$SOURCE_DIR/requirements-lock.txt" "$PACK_DIR/requirements-lock.txt"

rm -f "$ARCHIVE_PATH"
ditto -c -k --keepParent "$PACK_DIR" "$ARCHIVE_PATH"

ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
ARCHIVE_SIZE="$(stat -f '%z' "$ARCHIVE_PATH")"
sed \
    -e "s|__DOWNLOAD_URL__|$PACK_NAME.zip|g" \
    -e "s|__ARCHIVE_SHA256__|$ARCHIVE_SHA256|g" \
    -e "s|__ARCHIVE_SIZE__|$ARCHIVE_SIZE|g" \
    "$SOURCE_DIR/catalog-template.json" > "$ARTIFACT_DIR/catalog.json"

echo "$PACK_DIR"
echo "$ARCHIVE_PATH"
echo "SHA-256: $ARCHIVE_SHA256"
