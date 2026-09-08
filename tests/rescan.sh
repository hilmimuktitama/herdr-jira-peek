#!/bin/sh
# shellcheck disable=SC2016,SC1007 # Generated fixture scripts contain literal snippets; empty test values are deliberate.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-rescan.XXXXXX"); trap 'rm -rf "$tmp"' 0 1 2 15
mkdir -p "$tmp/bin" "$tmp/config" "$tmp/state"
cat > "$tmp/bin/twg" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TWG_LOG"
exit 97
EOF
chmod 700 "$tmp/bin/twg"
: > "$tmp/twg.log"
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="ABC|DEF"' 'MAX_CANDIDATES=3' > "$tmp/config/config.sh"
printf '%s\n' OLD-1 OLD-2 > "$tmp/state/candidates"
cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_LOG"
if [ "$1 $2" = "pane get" ]; then
  [ "${HERDR_GET_MODE:-ok}" = dead ] && exit 1
  [ "${HERDR_GET_MODE:-ok}" = moved ] && printf '%s\n' '{"result":{"pane":{"terminal_id":"other-terminal"}}}' || printf '%s\n' '{"result":{"pane":{"pane_id":"source-pane","terminal_id":"source-terminal"}}}'
  exit 0
fi
if [ "$1 $2" = "workspace list" ]; then printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"workspace-a"}]}}'; exit 0; fi
if [ "$1 $2" = "pane list" ]; then
  [ "${HERDR_GET_MODE:-ok}" = dead ] && printf '%s\n' '{"result":{"panes":[]}}' || printf '%s\n' '{"result":{"panes":[{"pane_id":"moved-pane","terminal_id":"source-terminal"}]}}'; exit 0
fi
if [ "$1 $2" = "pane read" ]; then
  if [ -n "${HERDR_READ_GATE:-}" ]; then
    : > "$HERDR_READ_STARTED"
    while [ ! -f "$HERDR_READ_GATE" ]; do sleep 0.02; done
  fi
  [ "${HERDR_READ_MODE:-ok}" = fail ] && exit 1
  case "${5:-}" in
    visible) printf '%s\n' "${HERDR_VISIBLE_TEXT-ABC-1 DEF-2 ABC-3}" ;;
    recent-unwrapped) printf '%s\n' "${HERDR_RECENT_TEXT-}" ;;
    detection) printf '%s\n' "${HERDR_DETECTION_TEXT-ABC-9 ABC-3}" ;;
    *) exit 1;;
  esac; exit 0
fi
exit 1
EOF
chmod 700 "$tmp/bin/herdr"; : > "$tmp/herdr.log"
export PATH="$tmp/bin:$PATH" HERDR_BIN_PATH=herdr TWG_BIN_PATH="$tmp/bin/twg" TWG_LOG="$tmp/twg.log" HERDR_LOG="$tmp/herdr.log" HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state" VIEWER_STATE_DIR="$tmp/state" HERDR_VIEWER_SOURCE_PANE=source-pane HERDR_VIEWER_SOURCE_TERMINAL=source-terminal
unset HERDR_SOCKET_PATH VIEWER_METADATA_MODE VIEWER_COORDINATOR_PID VIEWER_FZF_SOCKET

sh "$ROOT/scripts/viewer-rescan.sh"
[ "$(cat "$tmp/state/candidates")" = "$(printf '%s\n' ABC-3 DEF-2 ABC-1)" ] || exit 1
printf '%s\n' 'ok - visible-first newest ordering'

HERDR_VISIBLE_TEXT=ABC-1 HERDR_RECENT_TEXT='DEF-2 ABC-4 ABC-1' HERDR_DETECTION_TEXT='ABC-9 ABC-4' sh "$ROOT/scripts/viewer-rescan.sh"
[ "$(cat "$tmp/state/candidates")" = "$(printf '%s\n' ABC-1 ABC-4 DEF-2)" ] || exit 1
printf '%s\n' 'ok - recent-unwrapped fills after visible with dedup'

HERDR_VISIBLE_TEXT= HERDR_RECENT_TEXT= HERDR_DETECTION_TEXT='ABC-9 ABC-9 DEF-8 ABC-1' sh "$ROOT/scripts/viewer-rescan.sh"
[ "$(cat "$tmp/state/candidates")" = "$(printf '%s\n' ABC-1 DEF-8 ABC-9)" ] || exit 1
printf '%s\n' 'ok - detection fallback is deduplicated'

before=$(cat "$tmp/state/candidates")
if HERDR_READ_MODE=fail sh "$ROOT/scripts/viewer-rescan.sh"; then exit 1; fi
[ "$(cat "$tmp/state/candidates")" = "$before" ] && grep -Fq 'Could not read source terminal; keeping previous 3' "$tmp/state/status" || exit 1
printf '%s\n' 'ok - read failure preserves list with fixed status'
if HERDR_GET_MODE=dead sh "$ROOT/scripts/viewer-rescan.sh"; then exit 1; fi
grep -Fq 'Source terminal unavailable; keeping previous 3' "$tmp/state/status" || exit 1
printf '%s\n' 'ok - dead source has distinct fixed status'

HERDR_GET_MODE=moved sh "$ROOT/scripts/viewer-rescan.sh"
grep -Fq 'pane read moved-pane' "$tmp/herdr.log" || exit 1
printf '%s\n' 'ok - moved source resolves by terminal identity'
! grep -Eq 'plugin pane (open|close)' "$tmp/herdr.log" || exit 1
printf '%s\n' 'ok - rescan performs no layout operations'

before=$(cat "$tmp/state/candidates")
if HERDR_VISIBLE_TEXT= HERDR_RECENT_TEXT= HERDR_DETECTION_TEXT= sh "$ROOT/scripts/viewer-rescan.sh"; then exit 1; fi
[ "$(cat "$tmp/state/candidates")" = "$before" ] || exit 1
grep -Fq 'No Jira keys found; keeping previous 3' "$tmp/state/status" || exit 1
printf '%s\n' 'ok - no keys preserves list with distinct status'
[ ! -s "$tmp/twg.log" ] || exit 1
[ ! -e "$tmp/state/pending-snapshot" ] || exit 1
printf '%s\n' 'ok - rescan never invokes TWG or queues metadata'

# Observe progress while the source read is deliberately held open.
before=$(cat "$tmp/state/candidates")
HERDR_READ_GATE="$tmp/release" HERDR_READ_STARTED="$tmp/started" \
  sh "$ROOT/scripts/viewer-rescan.sh" --fzf > "$tmp/actions" &
worker=$!
attempt=0
while [ ! -e "$tmp/started" ] && [ "$attempt" -lt 100 ]; do
  sleep 0.02; attempt=$((attempt + 1))
done
progress_ok=1
[ -e "$tmp/started" ] || progress_ok=0
[ "$(cat "$tmp/state/candidates")" = "$before" ] || progress_ok=0
sh "$ROOT/scripts/viewer-rows.sh" header | grep -Fqx 'Rescanning source pane...' || progress_ok=0
[ ! -s "$tmp/actions" ] || progress_ok=0
: > "$tmp/release"
wait "$worker"
[ "$progress_ok" = 1 ] || exit 1
grep -Fq 'rebind(ctrl-g)+reload(' "$tmp/actions"
grep -Fqx 'Rescanned: 3 issues' "$tmp/state/status"
printf '%s\n' 'ok - rescan exposes progress before a delayed read and restores controls on completion'
if HERDR_READ_MODE=fail sh "$ROOT/scripts/viewer-rescan.sh" --fzf > "$tmp/actions"; then exit 1; fi
grep -Fq 'rebind(ctrl-g)+reload(' "$tmp/actions"
grep -Fq 'Could not read source terminal; keeping previous 3' "$tmp/state/status"
printf '%s\n' 'ok - failed background rescan restores controls and reports failure'
: > "$tmp/herdr.log"
sh "$ROOT/scripts/viewer-rescan.sh" --notify
awk '/notification show Rescanning Jira Peek.*--sound none/ { feedback=1 } /pane read/ { read_seen=1; if (!feedback) late=1 } END { exit !(feedback && read_seen && !late) }' "$tmp/herdr.log"
printf '%s\n' 'ok - older pickers receive quiet rescan feedback before reading the pane'
