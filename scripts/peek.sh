#!/bin/sh
# shellcheck source=scripts/common.sh
# Scan the focused pane's output for Jira keys, then review one in an adjacent pane.
set -eu
. "$(dirname "$0")/common.sh"
lock_acquire
if toggle_viewer; then exit 0; fi
require_fzf

pid=$(pane_id)
[ -n "$pid" ] || die 'no pane in context'
validate_pane_id "$pid" || die 'invalid pane in context'

candidate_tmp=$(mktemp "$HANDOFF_STATE_DIR/.candidates.XXXXXX") || die 'could not create candidate list'
trap 'rm -f "$candidate_tmp"; lock_release' 0
trap 'rm -f "$candidate_tmp"; lock_release; exit 1' 1 2 15
scan_candidates "$pid" "$candidate_tmp" || scan_status=$?

if [ "${scan_status:-0}" -eq 2 ]; then
  rm -f "$candidate_tmp"
  die 'could not read source pane'
fi
if [ "${scan_status:-0}" -eq 1 ] || [ ! -s "$candidate_tmp" ]; then
  rm -f "$candidate_tmp"
  die 'no Jira key found in this pane'
fi
mv "$candidate_tmp" "$CANDIDATES_FILE"
show "$(sed -n '1p' "$CANDIDATES_FILE")"
