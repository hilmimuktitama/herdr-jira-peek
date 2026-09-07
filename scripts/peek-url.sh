#!/bin/sh
# shellcheck source=scripts/common.sh
# Legacy URL entrypoint retained for explicit callers and regression coverage.
# The public manifest registers no link handler; Ctrl+click does not invoke it.
set -eu
. "$(dirname "$0")/common.sh"
lock_acquire
if toggle_viewer; then exit 0; fi
require_fzf
require_twg

url=${HERDR_PLUGIN_CLICKED_URL:-}
[ -n "$url" ] || die 'no clicked URL in context'

if ! key=$(key_from_url "$url"); then
  die 'clicked URL is not a configured Jira browse URL'
fi

candidate_tmp=$(mktemp "$HANDOFF_STATE_DIR/.candidates.XXXXXX") || die 'could not create candidate list'
trap 'rm -f "$candidate_tmp"; lock_release' 0
trap 'rm -f "$candidate_tmp"; lock_release; exit 1' 1 2 15
printf '%s\n' "$key" > "$candidate_tmp"
mv "$candidate_tmp" "$CANDIDATES_FILE"
show "$key"
