#!/bin/sh
# Remove only Peek for Jira's issue-cache files; preserve all other state.
set -eu
umask 077

state=${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}
cache=$state/cache
STATE=$state
CACHE=$cache
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/connection.sh
. "$DIR/connection.sh"

case "$state" in
  ''|/|.)
    printf '%s\n' 'Peek for Jira: refusing an unsafe state directory.' >&2
    exit 1
    ;;
esac

if [ -L "$state" ]; then
  printf '%s\n' 'Peek for Jira: refusing a symlinked state directory.' >&2
  exit 1
fi

if [ -L "$cache" ]; then
  printf '%s\n' 'Peek for Jira: refusing to clear a symlinked cache directory.' >&2
  exit 1
fi
if [ ! -e "$cache" ]; then
  printf '%s\n' 'Peek for Jira: issue cache is already empty.'
  exit 0
fi
if [ ! -d "$cache" ]; then
  printf '%s\n' 'Peek for Jira: cache path is not a directory.' >&2
  exit 1
fi

# Advance the epoch under the same lock used for request publication. This
# prevents a request that started before this action from restoring old data.
connection_lock || { printf '%s\n' 'Peek for Jira: connection state is busy.' >&2; exit 1; }
trap 'connection_unlock' 0
trap 'exit 1' 1 2 15
connection_read_marker || exit 1
CONNECTION_ID=$connection_saved_id
connection_new_epoch || exit 1
removed=0
# Deliberately do not recurse. The runtime stores issue payloads and temporary
# fetch files directly in this directory; session state and diagnostics live
# elsewhere and must survive a cache clear.
for entry in "$cache"/* "$cache"/.[!.]* "$cache"/..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  if [ -f "$entry" ] && [ ! -L "$entry" ]; then
    rm -f "$entry" || {
      printf '%s\n' "Peek for Jira: could not remove a cache file under $cache" >&2
      exit 1
    }
    removed=$((removed + 1))
  fi
done
printf 'Peek for Jira: cleared %s issue-cache file(s); other plugin state was kept.\n' "$removed"
