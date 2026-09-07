#!/bin/sh
# shellcheck disable=SC1007,SC2329 # Empty state values and exit cleanup are intentional.
# shellcheck source=scripts/common.sh
set -eu
. "$(dirname "$0")/common.sh"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
state=${VIEWER_STATE_DIR:?}
status_file="$state/status"
source_pane_arg=${HERDR_VIEWER_SOURCE_PANE:-}; source_terminal_arg=${HERDR_VIEWER_SOURCE_TERMINAL:-}
write_status() { status_tmp=$(mktemp "$state/.status.XXXXXX") || return 0; printf '%s\n' "$1" >"$status_tmp" && mv "$status_tmp" "$status_file"; rm -f "$status_tmp"; }
previous=$(wc -l < "$CANDIDATES_FILE" | tr -d ' ')
case "$previous" in ''|*[!0-9]*) previous=0;; esac
validate_pane_id "$source_pane_arg" || { write_status "Source terminal unavailable; keeping previous $previous"; exit 2; }
validate_terminal_id "$source_terminal_arg" || { write_status "Source terminal unavailable; keeping previous $previous"; exit 2; }
got=$(mktemp "$state/.rescan-keys.XXXXXX") || exit 1
check=; request_tmp=
cleanup() { rm -f "$got" "$check" "$request_tmp"; }
trap cleanup 0
trap 'cleanup; trap - 0; exit 1' 1 2 15
check=$(mktemp "$state/.rescan-pane.XXXXXX") || exit 1
if ! "$HERDR" pane get "$source_pane_arg" >"$check" 2>/dev/null || ! jq -er --arg t "$source_terminal_arg" '.result.pane.terminal_id == $t' "$check" >/dev/null 2>&1; then
  resolved_source=$(resolve_terminal_pane "$source_terminal_arg" 2>/dev/null || true)
  validate_pane_id "$resolved_source" || { rm -f "$check"; write_status "Source terminal unavailable; keeping previous $previous"; exit 2; }
  source_pane_arg=$resolved_source
fi
rm -f "$check"
scan_rc=0; scan_candidates "$source_pane_arg" "$got" || scan_rc=$?
if [ "$scan_rc" -eq 1 ]; then write_status "No Jira keys found; keeping previous $previous"; exit 1; fi
if [ "$scan_rc" -ne 0 ]; then write_status "Could not read source terminal; keeping previous $previous"; exit 2; fi
mv "$got" "$CANDIDATES_FILE"
new_count=$(wc -l < "$CANDIDATES_FILE" | tr -d ' ')
write_status "Rescanned: $new_count issues"
case "${VIEWER_METADATA_MODE:-}" in
live)
  if ! case "${VIEWER_COORDINATOR_PID:-}" in ''|*[!0-9]*) false;; *) kill -0 "$VIEWER_COORDINATOR_PID" 2>/dev/null && [ -e "$state/coordinator-ready" ];; esac; then
    VIEWER_NOTIFY=0 sh "$DIR/viewer-fetch.sh" --all >/dev/null 2>&1 || true
  else
  request_tmp=$(mktemp "$state/.snapshot.XXXXXX") || exit 0
  cp "$CANDIDATES_FILE" "$request_tmp" && mv "$request_tmp" "$state/pending-snapshot"
  fi
  ;;
batch)
  VIEWER_NOTIFY=0 sh "$DIR/viewer-fetch.sh" --all >/dev/null 2>&1 || true
  ;;
*) : ;;
esac
exit 0
