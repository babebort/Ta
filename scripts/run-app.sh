#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
APP_BUNDLE_DIR="$PROJECT_ROOT_DIR/artifacts/拓.app"

if [[ ! -d "$APP_BUNDLE_DIR" ]]; then
    "$PROJECT_ROOT_DIR/scripts/build-app.sh"
fi

open "$APP_BUNDLE_DIR"
