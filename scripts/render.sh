#!/bin/sh
# shellcheck source=scripts/common.sh
# Render one cached issue as readable text. Usage: render.sh <KEY>
set -eu
SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RENDER_JQ="$SCRIPT_DIR/render.jq"
. "$SCRIPT_DIR/common.sh"
[ -r "$RENDER_JQ" ] || die 'render.jq is missing or unreadable'
# shellcheck source=scripts/style.sh
. "$SCRIPT_DIR/style.sh"
peek_style
viewer_preview=0
if [ "${1:-}" = --viewer-preview ]; then viewer_preview=1; shift; fi
key=${1:-}
validate_key "$key" || die 'invalid Jira issue key'
if [ "$viewer_preview" -eq 1 ] && [ -n "${VIEWER_STATE_DIR:-}" ]; then
  if [ ! -s "$VIEWER_STATE_DIR/rows/$key" ]; then
    # Only the initial metadata batch is pending; older keys fetch on demand.
    if ! awk -v k="$key" -v max="$MAX_CANDIDATES" '$0 == k { found=(NR > max); exit } END { exit !found }' "$CANDIDATES_FILE"; then
      printf '%s\n' 'Fetching issue...'
      exit 0
    fi
  elif [ -e "$VIEWER_STATE_DIR/failed/$key" ]; then
    detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' "$FETCH_ERROR_GENERIC")
    printf 'Could not load %s: %s\n' "$key" "$detail"
    exit 1
  fi
fi
f=
cleanup() {
  [ -z "$f" ] || fetch_cleanup "$f"
  fetch_work_cleanup
}
trap cleanup 0
trap 'cleanup; trap - 0; exit 1' 1 2 15

if [ "${JIRA_PEEK_RENDER_PUBLISHED:-}" = 1 ] \
  && [ -s "$CACHE/$key.json" ] && [ ! -L "$CACHE/$key.json" ] \
  && cache_entry_valid "$key"; then
  f=$CACHE/$key.json
elif fetch "$key" >/dev/null; then
  f=$FETCHED_FILE
else
  detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' "$FETCH_ERROR_GENERIC")
  if [ "$JIRA_BACKEND" = rest ]; then die "Jira could not read $key: $detail"; fi
  die "TWG could not read $key: $detail"
fi
# FZF_PREVIEW_COLUMNS is the useful width when this is a preview. COLUMNS and
# tput keep direct and less-backed renders readable as well.
preview=false
columns=${FZF_PREVIEW_COLUMNS:-}
case "$columns" in
  ''|0*|*[!0-9]*) columns='' ;;
  *) preview=true ;;
esac
if [ -z "$columns" ]; then
  columns=${COLUMNS:-}
  case "$columns" in
    ''|0*|*[!0-9]*) columns='' ;;
  esac
fi
if [ -z "$columns" ] && command -v tput >/dev/null 2>&1; then
  columns=$(tput cols 2>/dev/null || true)
  case "$columns" in
    ''|0*|*[!0-9]*) columns='' ;;
  esac
fi
[ -n "$columns" ] || columns=80
canonical_url=
# Keep the canonical link available when a user explicitly selects `link` in
# preview fields. The default preview omits it from the output.
canonical_url=$(issue_url "$key") || die 'could not determine the issue URL'

# Leave a little room for a preview divider and its padding. A minimum of one
# keeps the splitter safe even when a very narrow value is supplied by fzf.
wrap_width=$((columns - 2))
[ "$wrap_width" -gt 0 ] || wrap_width=1
# fzf retains these lines and reflows them while resizing. Use a stable reading
# width rather than the opening pane width. Bound each logical line because
# fzf scrolls whole lines: an unbounded wrapped paragraph can hide its tail.
[ "$viewer_preview" -eq 0 ] || wrap_width=80

fields_csv=${READER_FIELDS-status,assignee,updated,link,description,comments}
[ "$preview" = true ] && fields_csv=${PREVIEW_FIELDS-status,assignee,updated,description,comments}
selected_fields=$(jq -Rn --arg csv "$fields_csv" '$csv | split(",") | map(select(length > 0))') \
  || die 'could not parse configured Jira fields'
field_labels=${FIELD_LABELS:-}

if ! rendered=$(jq -L "$SCRIPT_DIR" -r \
  --arg url "$canonical_url" \
  --argjson preview "$preview" \
  --argjson selected_fields "$selected_fields" \
  --arg field_labels "$field_labels" \
  -f "$RENDER_JQ" "$f" 2>/dev/null); then
  die 'could not render issue content'
fi
connection_assert_current || die 'Connection changed; close and reopen Peek.'
printf '%s\n' "$rendered" | LC_ALL=C awk -v width="$wrap_width" -v bounded_preview="$viewer_preview" \
     -v style="$PEEK_STYLE" -v labels="$field_labels" -v bold="$PEEK_BOLD" -v reset="$PEEK_RESET" \
     -f "$SCRIPT_DIR/text-format.awk"

fetch_cleanup "$f"
f=
trap - 0 1 2 15
