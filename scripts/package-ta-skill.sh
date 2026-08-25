#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_ROOT_DIR/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
RELEASE_DIR="${2:-$PROJECT_ROOT_DIR/artifacts/release/v$VERSION}"
SKILL_DIR="$PROJECT_ROOT_DIR/Integrations/AgentSkill/ta"
ARCHIVE_PATH="$RELEASE_DIR/Ta-Agent-Skill-$VERSION.zip"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid Agent Skill release version: $VERSION" >&2
    exit 1
fi
test -f "$SKILL_DIR/SKILL.md"
grep -q '^name: ta$' "$SKILL_DIR/SKILL.md"
grep -q '^description:' "$SKILL_DIR/SKILL.md"
test -x "$SKILL_DIR/scripts/check-ta.sh"

mkdir -p "$RELEASE_DIR"
rm -f "$ARCHIVE_PATH"
DITTONORSRC=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$SKILL_DIR" "$ARCHIVE_PATH"
echo "$ARCHIVE_PATH"
