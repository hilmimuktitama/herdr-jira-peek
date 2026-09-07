#!/bin/sh
# shellcheck source=scripts/common.sh
# Show a loading placeholder without triggering a second fetch.
set -eu
. "$(dirname "$0")/common.sh"
key=${1:-}
validate_key "$key" || exit 1
if [ -n "${VIEWER_STATE_DIR:-}" ] && [ ! -s "$VIEWER_STATE_DIR/rows/$key" ]; then
  printf '%s\n' 'Fetching issue...'
elif [ -n "${VIEWER_STATE_DIR:-}" ] && [ -e "$VIEWER_STATE_DIR/failed/$key" ]; then
  detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' 'TWG request failed')
  printf 'Could not load %s: %s\n' "$key" "$detail"
  exit 1
elif cache_entry_valid "$key"; then
  JIRA_PEEK_RENDER_PUBLISHED=1 exec sh "$(dirname "$0")/render.sh" "$key"
else
  # Picker rows contain only metadata. Fetch comments/full detail only when
  # the user previews or opens this selected issue.
  exec sh "$(dirname "$0")/render.sh" "$key"
fi
