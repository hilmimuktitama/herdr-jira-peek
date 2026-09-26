#!/bin/sh
# Fictional, offline coverage for the selection-to-highlight UI bridge.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-highlight-ui.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 15
mkdir -m 700 "$tmp/state"
state=$tmp/state
key_file=$state/selected-key
export VIEWER_STATE_DIR="$state" VIEWER_KEY_FILE="$key_file"
export VIEWER_SOURCE_HIGHLIGHT_ENABLED=1
unset VIEWER_CONNECTION_ID VIEWER_MODERN_FOOTER

printf '%s\n' DEMO-17 DEMO-23 > "$state/candidates"
printf '%s\n' DEMO-17 > "$key_file"

# Selecting a listed fictional key updates both the selected-key file and the
# worker request through atomic replacements in the private state directory.
sh "$ROOT/scripts/viewer-ui.sh" focus DEMO-23 >/dev/null
[ "$(cat "$key_file")" = DEMO-23 ] || exit 1
[ "$(cat "$state/highlight-request")" = DEMO-23 ] || exit 1
for leftover in "$state"/.key.* "$state"/.highlight-request.*; do
  [ ! -e "$leftover" ] || exit 1
done
printf '%s\n' 'ok - listed selection updates the key and highlight request atomically'

# Empty focus clears the worker request while leaving the last selected key as
# viewer state. Invalid syntax and keys outside the candidate snapshot fail.
sh "$ROOT/scripts/viewer-ui.sh" focus '' >/dev/null
[ -f "$state/highlight-request" ] || exit 1
empty_request=
IFS= read -r empty_request < "$state/highlight-request" || true
[ -z "$empty_request" ] || exit 1
if sh "$ROOT/scripts/viewer-ui.sh" focus 'DEMO-23;touch-bad' >/dev/null 2>&1; then exit 1; fi
if sh "$ROOT/scripts/viewer-ui.sh" focus DEMO-99 >/dev/null 2>&1; then exit 1; fi
[ "$(cat "$key_file")" = DEMO-23 ] || exit 1
empty_request=nonempty
IFS= read -r empty_request < "$state/highlight-request" || true
[ -z "$empty_request" ] || exit 1
printf '%s\n' 'ok - empty focus clears and invalid or noncandidate keys are rejected'

# Status rendering accepts only fixed phrases or a small numeric match count.
# Header mode places the source status after the shortcut header.
printf '%s\n' 'Source: 2 visible matches' > "$state/highlight-status"
VIEWER_HAS_FOOTER=0 sh "$ROOT/scripts/viewer-rows.sh" header > "$tmp/header"
grep -Fqx 'Enter Read · Ctrl-U Clear · Ctrl-G Rescan · F1 Help · Esc Close' "$tmp/header" || exit 1
grep -Fqx 'Source: 2 visible matches' "$tmp/header" || exit 1
[ "$(tail -n 1 "$tmp/header")" = 'Source: 2 visible matches' ] || exit 1
printf '%s\n' 'ok - header mode places allowlisted source status below shortcuts'

# Footer mode places status before shortcuts; hostile raw text and control
# bytes must never be reflected into the picker chrome.
VIEWER_HAS_FOOTER=1 FZF_COLUMNS=80 sh "$ROOT/scripts/viewer-rows.sh" footer > "$tmp/footer"
grep -Fq 'Source: 2 visible matches' "$tmp/footer" || exit 1
grep -Fq 'Enter Read' "$tmp/footer" || exit 1
source_line=$(grep -n -F 'Source: 2 visible matches' "$tmp/footer" | cut -d: -f1)
shortcut_line=$(grep -n -F 'Enter Read' "$tmp/footer" | cut -d: -f1)
[ "$source_line" -lt "$shortcut_line" ] || exit 1

printf '%s\n' 'Source: DEMO-17 visible matches; printf hacked' > "$state/highlight-status"
[ -z "$(VIEWER_HAS_FOOTER=1 sh "$ROOT/scripts/viewer-rows.sh" source-status)" ] || exit 1
printf 'Source: 1 visible match\001INJECTED\n' > "$state/highlight-status"
[ -z "$(VIEWER_HAS_FOOTER=1 sh "$ROOT/scripts/viewer-rows.sh" source-status)" ] || exit 1
printf '%s\n' 'Source: highlight unavailable' > "$state/highlight-status"
[ "$(VIEWER_HAS_FOOTER=1 sh "$ROOT/scripts/viewer-rows.sh" source-status)" = 'Source: highlight unavailable' ] || exit 1
printf '%s\n' 'Source: position uncertain' > "$state/highlight-status"
[ "$(VIEWER_HAS_FOOTER=1 sh "$ROOT/scripts/viewer-rows.sh" source-status)" = 'Source: position uncertain' ] || exit 1
printf '%s\n' 'ok - footer orders source status before shortcuts and filters unsafe status'

printf '%s\n' 'Source: native highlight' > "$state/highlight-status"
[ -z "$(sh "$ROOT/scripts/viewer-rows.sh" source-status)" ] || exit 1
healthy_layout=$(VIEWER_HAS_FOOTER=1 FZF_COLUMNS=80 FZF_LINES=24 sh "$ROOT/scripts/viewer-ui.sh" layout)
: > "$state/highlight-status"
[ "$(VIEWER_HAS_FOOTER=1 FZF_COLUMNS=80 FZF_LINES=24 sh "$ROOT/scripts/viewer-ui.sh" layout)" = "$healthy_layout" ] || exit 1
native_status='Source: native highlight requires Herdr update'
printf '%s\n' "$native_status" > "$state/highlight-status"
[ "$(sh "$ROOT/scripts/viewer-rows.sh" source-status)" = "$native_status" ] || exit 1
VIEWER_HAS_FOOTER=1 VIEWER_MODERN_FOOTER=1 sh "$ROOT/scripts/viewer-ui.sh" refresh-source-status > "$tmp/native-status"
grep -Fq "$native_status" "$tmp/native-status" || exit 1
printf '%s\n' 'ok - successful highlighting uses no status row; upgrade guidance stays visible'
