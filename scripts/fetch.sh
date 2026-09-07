#!/bin/sh
# shellcheck source=scripts/common.sh
# shellcheck disable=SC2329 # Cleanup is invoked indirectly by exit traps.
# Warm the cache for one key and print a picker row: KEY  STATUS  SUMMARY.
set -eu
. "$(dirname "$0")/common.sh"
key=${1:-}
validate_key "$key" || die 'invalid Jira issue key'
f=
cleanup() {
  [ -z "$f" ] || fetch_cleanup "$f"
  fetch_work_cleanup
}
trap cleanup 0
trap 'cleanup; trap - 0; exit 1' 1 2 15

if fetch "$key" >/dev/null; then
  f=$FETCHED_FILE
  fetch_status=0
  jq -r '
    def row_text: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; " ");
    [.key, ((.status.name // "?") | row_text), ((.summary // "") | row_text)] | @tsv
  ' "$f" || fetch_status=$?
  fetch_cleanup "$f"
  f=
  trap - 0 1 2 15
  exit "$fetch_status"
else
  detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' 'TWG request failed')
  die "could not read $key: $detail"
fi
