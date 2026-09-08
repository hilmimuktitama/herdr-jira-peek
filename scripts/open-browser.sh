#!/bin/sh
# shellcheck source=scripts/common.sh
# Open or copy a validated Jira key. With no argument, use the last selected key.
set -eu
. "$(dirname "$0")/common.sh"

mode=open
if [ "$#" -eq 0 ]; then
  # Explicit viewer callbacks inherit their source; workspace actions resolve
  # the focused source/viewer instead of using another agent's last selection.
  if [ -z "${HERDR_VIEWER_SOURCE_TERMINAL:-}" ]; then
    lock_acquire
    resolve_action_source
    lock_release
  fi
  [ -s "$KEY_FILE" ] || die 'nothing peeked yet'
  key=$(sed -n '1p' "$KEY_FILE")
elif [ "$#" -eq 2 ]; then
  mode=$1
  key=$2
else
  die 'invalid browser action arguments'
fi

validate_key "$key" || die 'invalid Jira issue key'
case "$mode" in
  --key)
    save_key "$key"
    open_url "$(issue_url "$key")"
    ;;
  --select)
    save_key "$key"
    ;;
  --copy-key)
    copy_text "$key"
    ;;
  --copy-link)
    copy_text "$(issue_url "$key")"
    ;;
  --refresh)
    invalidate_cache "$key"
    ;;
  open)
    open_url "$(issue_url "$key")"
    ;;
  *)
    die 'unknown browser action'
    ;;
esac
