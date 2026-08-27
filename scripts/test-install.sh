#!/bin/bash

set -euo pipefail

PROJECT_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ta-installer-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT_DIR/Resources/Info.plist")"
RELEASE_DIR="$TEST_ROOT/release"
CLI_PACKAGE_DIR="$TEST_ROOT/ta-cli-$VERSION"
SKILL_PACKAGE_DIR="$TEST_ROOT/skill/ta"
INSTALL_HOME="$TEST_ROOT/home"
TAMPERED_RELEASE_DIR="$TEST_ROOT/tampered-release"
TAMPERED_HOME="$TEST_ROOT/tampered-home"

mkdir -p "$RELEASE_DIR" "$CLI_PACKAGE_DIR/bin" "$SKILL_PACKAGE_DIR/scripts"

printf '#!/bin/sh\nprintf '\''{"ok":true,"data":{"bridge":"ready"}}\\n'\''\n' > "$CLI_PACKAGE_DIR/bin/ta"
chmod 755 "$CLI_PACKAGE_DIR/bin/ta"
printf '%s\n' '---' 'name: ta' 'description: Test Ta skill.' '---' > "$SKILL_PACKAGE_DIR/SKILL.md"
printf '#!/bin/sh\nexec "$HOME/.local/bin/ta" status --json\n' > "$SKILL_PACKAGE_DIR/scripts/check-ta.sh"
chmod 755 "$SKILL_PACKAGE_DIR/scripts/check-ta.sh"

COPYFILE_DISABLE=1 tar -C "$TEST_ROOT" -czf \
    "$RELEASE_DIR/Ta-CLI-$VERSION-macOS-universal.tar.gz" \
    "ta-cli-$VERSION"
DITTONORSRC=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
    "$SKILL_PACKAGE_DIR" \
    "$RELEASE_DIR/Ta-Agent-Skill-$VERSION.zip"

(
    cd "$RELEASE_DIR"
    shasum -a 256 \
        "Ta-CLI-$VERSION-macOS-universal.tar.gz" \
        "Ta-Agent-Skill-$VERSION.zip" \
        > SHA256SUMS.txt
)

for run in 1 2; do
    TA_INSTALL_VERSION="$VERSION" \
    TA_INSTALL_ROOT="$INSTALL_HOME" \
    TA_RELEASE_BASE_URL="file://$RELEASE_DIR" \
    TA_SKIP_SHELL_PROFILE=1 \
    TA_SKIP_STATUS_CHECK=1 \
    bash "$PROJECT_ROOT_DIR/scripts/install.sh"
done

test -x "$INSTALL_HOME/.local/bin/ta"
test -f "$INSTALL_HOME/.codex/skills/ta/SKILL.md"
test -f "$INSTALL_HOME/.agents/skills/ta/SKILL.md"
test "$($INSTALL_HOME/.local/bin/ta status --json)" = '{"ok":true,"data":{"bridge":"ready"}}'

ditto "$RELEASE_DIR" "$TAMPERED_RELEASE_DIR"
printf 'tampered\n' >> "$TAMPERED_RELEASE_DIR/Ta-Agent-Skill-$VERSION.zip"
if TA_INSTALL_VERSION="$VERSION" \
    TA_INSTALL_ROOT="$TAMPERED_HOME" \
    TA_RELEASE_BASE_URL="file://$TAMPERED_RELEASE_DIR" \
    TA_SKIP_SHELL_PROFILE=1 \
    TA_SKIP_STATUS_CHECK=1 \
    bash "$PROJECT_ROOT_DIR/scripts/install.sh" > "$TEST_ROOT/tampered-output.log" 2>&1; then
    printf 'Tampered installer test unexpectedly succeeded.\n' >&2
    exit 1
fi
grep -q 'SHA-256 校验不一致' "$TEST_ROOT/tampered-output.log"
test ! -e "$TAMPERED_HOME/.local/bin/ta"

printf 'Ta installer clean-home, idempotency, and checksum rejection tests passed.\n'
