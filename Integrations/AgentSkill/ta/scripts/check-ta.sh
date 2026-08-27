#!/bin/sh
set -eu

if command -v ta >/dev/null 2>&1; then
    exec ta status --json
fi

if [ -x "$HOME/.local/bin/ta" ]; then
    exec "$HOME/.local/bin/ta" status --json
fi

printf '%s\n' '{"ok":false,"error":{"code":"TA_CLI_NOT_INSTALLED","message":"ta CLI is not installed","hint":"Install it from Ta Settings > Agent or https://github.com/kangarooking/Ta/releases/latest/download/install.sh"}}'
exit 1
