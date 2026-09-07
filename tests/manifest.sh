#!/bin/sh
# shellcheck disable=SC2016,SC1007 # Manifest fixtures contain literal shell snippets and empty test values.
# Static contract checks for the Herdr plugin manifest. Keep this dependency
# free so CI can run it before installing a Herdr CLI.
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
MANIFEST=$ROOT/herdr-plugin.toml

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

[ -r "$MANIFEST" ] || fail 'manifest exists'

grep -Fqx 'id = "jira-peek"' "$MANIFEST" \
  || fail 'manifest plugin id'
grep -Fqx 'platforms = ["macos", "linux"]' "$MANIFEST" \
  || fail 'manifest platform declarations'

for action in peek open-browser setup doctor clear-cache; do
  grep -Fqx "id = \"$action\"" "$MANIFEST" \
    || fail "manifest action $action"
done
for script in peek.sh open-browser.sh setup.sh doctor.sh clear-cache.sh viewer.sh; do
  [ -f "$ROOT/scripts/$script" ] || fail "manifest command target $script exists"
done

# Every declared shell command must use the checked-in script and each action
# ID must be unique. These checks catch typoed or stale manifest entries.
command_count=$(awk '/^command = \["sh", "scripts\// { count++ } END { print count + 0 }' "$MANIFEST")
[ "$command_count" -ge 4 ] || fail 'manifest declares all action/pane commands'
duplicate_action=$(awk -F '"' '/^id = "/ { print $2 }' "$MANIFEST" \
  | sort | uniq -d)
[ -z "$duplicate_action" ] || fail 'manifest IDs are unique'

# A generic link handler would intercept unrelated browser links and is
# therefore forbidden by the plugin contract.
if grep -q '^\[\[link_handlers\]\]' "$MANIFEST"; then
  fail 'manifest does not register an implicit link handler'
fi
pass 'Herdr manifest and action/link contract'
