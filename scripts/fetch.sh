#!/bin/sh
# shellcheck source=scripts/common.sh
# shellcheck disable=SC2329 # Cleanup is invoked indirectly by exit traps.
# Warm the cache for one key and print a configured picker row (key is always first).
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
  connection_assert_current || die 'Connection changed; retry with the current connection.'
  fetch_status=0
  picker_row "$f" || fetch_status=$?
  fetch_cleanup "$f"
  f=
  trap - 0 1 2 15
  exit "$fetch_status"
else
  detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' "$FETCH_ERROR_GENERIC")
  die "could not read $key: $detail"
fi
