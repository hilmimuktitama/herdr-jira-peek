#!/bin/sh
# shellcheck disable=SC2016,SC2329 # fzf reload and exit-trap callbacks are intentionally indirect.
# shellcheck source=scripts/common.sh
# Fetch picker rows; --all makes one capped metadata request.
set -eu
. "$(dirname "$0")/common.sh"
state=${VIEWER_STATE_DIR:?}
arg=${1:-}
if [ "$arg" = --queue-refresh ]; then
  validate_key "${2:-}" || exit 1
  case "${VIEWER_COORDINATOR_PID:-}" in ''|*[!0-9]*) coordinator_live=0;; *) kill -0 "$VIEWER_COORDINATOR_PID" 2>/dev/null && [ -e "$state/coordinator-ready" ] && coordinator_live=1 || coordinator_live=0;; esac
  if [ "${VIEWER_METADATA_MODE:-}" != live ] || [ "$coordinator_live" -ne 1 ]; then
    exec sh "$DIR/viewer-fetch.sh" --refresh "$2"
  fi
  mkdir -p "$state/pending-refresh" || exit 1
  : > "$state/pending-refresh/$2"
  exit 0
fi
if [ "$arg" = --watch ]; then
  # This polls only viewer-owned request files; it never polls terminal output.
  pending="$state/pending-snapshot"
  watch_cleanup() { rm -f "$state/coordinator-ready"; }
  trap watch_cleanup 0
  trap 'watch_cleanup; trap - 0; exit 1' 1 2 15
  : > "$state/coordinator-ready"
  while :; do
    if [ -s "$pending" ]; then
      request=$(mktemp "$state/.request.XXXXXX") || exit 0
      mv "$pending" "$request" || { rm -f "$request"; continue; }
      VIEWER_NOTIFY=1 sh "$DIR/viewer-fetch.sh" --all "$request" || true
      rm -f "$request"
    else
      for refresh in "$state/pending-refresh"/*; do
        [ -f "$refresh" ] || continue
        key=${refresh##*/}; rm -f "$refresh"
        VIEWER_NOTIFY=1 sh "$DIR/viewer-fetch.sh" --refresh "$key" || true
      done
      sleep 0.1
    fi
  done
fi
notify() {
  [ "${VIEWER_NOTIFY:-1}" = 1 ] && [ -n "${VIEWER_FZF_SOCKET:-}" ] && command -v curl >/dev/null 2>&1 || return 0
  (cd "${VIEWER_STATE_DIR:?}" || exit 0
   i=0; while [ ! -S "$VIEWER_FZF_SOCKET" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
   [ -S "$VIEWER_FZF_SOCKET" ] || exit 0
   i=0
   while [ "$i" -lt 3 ]; do
      curl -sS --max-time 1 --unix-socket "$VIEWER_FZF_SOCKET" -X POST http://localhost -d 'reload(sh "$DIR/viewer-rows.sh")+refresh-preview' >/dev/null 2>&1 && exit 0
     i=$((i + 1)); sleep 0.05
   done
  )
}
if [ "$arg" = --refresh ]; then
  key=${2:-}; validate_key "$key" || exit 1
  cache_invalidate "$key" || exit 1
  rm -f "$state/rows/$key" "$state/failed/$key"
  keys=$(mktemp "$state/.metadata-keys.XXXXXX") || exit 1
  raw=$(mktemp "$state/.metadata-json.XXXXXX") || { rm -f "$keys"; exit 1; }
  stderr=$(mktemp "$state/.metadata-stderr.XXXXXX") || { rm -f "$keys" "$raw"; exit 1; }
  row_tmp=
  fetch_cleanup() { rm -f "$keys" "$raw" "$stderr" "$row_tmp"; }
  trap fetch_cleanup 0
  trap 'fetch_cleanup; trap - 0; exit 1' 1 2 15
  printf '%s\n' "$key" > "$keys"
  batch_status=0
  run_twg_metadata_batch "$keys" "$raw" "$stderr" || batch_status=$?
  row_tmp=$(mktemp "$state/rows/.$key.XXXXXX") || exit 1
  if [ "$batch_status" -eq 0 ] && metadata_row "$raw" "$key" > "$row_tmp"; then
    mv "$row_tmp" "$state/rows/$key"
    rm -f "$state/failed/$key"
    clear_fetch_error "$key" || true
  else
    if [ "$batch_status" -eq 127 ]; then
      batch_prefix='TWG CLI unavailable; install the official Atlassian TWG CLI, ensure it is on PATH, then run twg setup'
    elif is_twg_auth_error "$stderr" "$raw"; then
      batch_prefix='TWG is not authenticated or configured; run twg setup, then retry'
    else
      batch_prefix='Jira request failed'
    fi
    record_fetch_error "$key" "$batch_prefix" '' "$stderr" || true
    printf '%s\t?\t(could not load)\n' "$key" > "$row_tmp"
    mv "$row_tmp" "$state/rows/$key"
    : > "$state/failed/$key"
  fi
  notify
  exit 0
fi
if [ "$arg" = --all ]; then
  snapshot_input=${2:-$CANDIDATES_FILE}
  keys=$(mktemp "$state/.metadata-keys.XXXXXX") || exit 0
  raw=$(mktemp "$state/.metadata-json.XXXXXX") || { rm -f "$keys"; exit 0; }
  stderr=$(mktemp "$state/.metadata-stderr.XXXXXX") || { rm -f "$keys" "$raw"; exit 0; }
  row_tmp=
  fetch_cleanup() { rm -f "$keys" "$raw" "$stderr" "$row_tmp"; }
  trap fetch_cleanup 0
  trap 'fetch_cleanup; trap - 0; exit 1' 1 2 15
  count=0
  while IFS= read -r key || [ -n "$key" ]; do
    validate_key "$key" || continue
    [ "$count" -lt "$MAX_CANDIDATES" ] || break
    grep -Fqx "$key" "$keys" 2>/dev/null && continue
    printf '%s\n' "$key" >> "$keys"
    count=$((count + 1))
  done < "$snapshot_input"
  if [ "$count" -eq 0 ]; then
    : > "$state/coordinator-done"
    exit 0
  fi

  batch_status=0
  run_twg_metadata_batch "$keys" "$raw" "$stderr" || batch_status=$?
  if [ "$batch_status" -eq 127 ]; then
    batch_prefix='TWG CLI unavailable; install the official Atlassian TWG CLI, ensure it is on PATH, then run twg setup'
  elif [ "$batch_status" -ne 0 ] && is_twg_auth_error "$stderr" "$raw"; then
    batch_prefix='TWG is not authenticated or configured; run twg setup, then retry'
  elif [ "$batch_status" -ne 0 ]; then
    batch_prefix='Jira request failed'
  fi

  while IFS= read -r key || [ -n "$key" ]; do
    row_tmp=$(mktemp "$state/rows/.$key.XXXXXX") || continue
    row_status=0
    if [ "$batch_status" -eq 0 ]; then
      metadata_row "$raw" "$key" > "$row_tmp" || row_status=1
      [ "$row_status" -eq 0 ] || record_fetch_error "$key" 'Jira response omitted requested issue' '' "$stderr" || true
    else
      row_status=1
      record_fetch_error "$key" "$batch_prefix" '' "$stderr" || true
    fi
    if [ "$row_status" -eq 0 ]; then
      mv "$row_tmp" "$state/rows/$key"
      rm -f "$state/failed/$key"
      clear_fetch_error "$key" || true
    else
      printf '%s\t?\t(could not load)\n' "$key" > "$row_tmp"
      mv "$row_tmp" "$state/rows/$key"
      : > "$state/failed/$key"
    fi
  done < "$keys"
  : > "$state/coordinator-done"
  notify
  exit 0
fi
[ "$arg" = --refresh ] || key=$arg
validate_key "$key" || exit 1
tmp=$(mktemp "$state/rows/.$key.XXXXXX") || exit 1
f=
cleanup_worker() {
  rm -f "$tmp"
  [ -z "$f" ] || fetch_cleanup "$f"
  fetch_work_cleanup
}
trap cleanup_worker 0
trap 'cleanup_worker; trap - 0; exit 1' 1 2 15
if fetch "$key" >/dev/null; then
  f=$FETCHED_FILE
  fetch_ok=1
  if ! jq -r 'def t: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; " "); [.key, (if (.status | type) == "object" then (.status.name // "?") else "?" end | t), ((.summary // "") | t)] | @tsv' "$f" > "$tmp"; then
    fetch_ok=0
    : > "$state/failed/$key"
    printf '%s\t?\t(could not load)\n' "$key" > "$tmp"
  fi
  fetch_cleanup "$f"
  f=
else
  fetch_ok=0
  : > "$state/failed/$key"
  printf '%s\t?\t(could not load)\n' "$key" > "$tmp"
fi
mv "$tmp" "$state/rows/$key"
if [ "$fetch_ok" -eq 1 ]; then rm -f "$state/failed/$key"; fi
trap - 0 1 2 15
notify
