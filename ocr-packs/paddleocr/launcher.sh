#!/bin/zsh

set -euo pipefail

PACK_SOURCE_DIR="${0:A:h}"
exec "$PACK_SOURCE_DIR/.venv/bin/python" "$PACK_SOURCE_DIR/adapter.py" "$@"
