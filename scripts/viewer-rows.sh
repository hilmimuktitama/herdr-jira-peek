#!/bin/sh
# shellcheck disable=SC1007 # Empty UI state values are intentional.
# shellcheck source=scripts/common.sh
# Render the ordered, atomically published picker snapshot.
set -eu
DIR=${DIR:-$(CDPATH='' cd "${0%/*}" && pwd)}
state=${VIEWER_STATE_DIR:?}
status_line() {
  status_value=$(sed -n '1p' "$state/status" 2>/dev/null || true)
  case "$status_value" in *[![:print:]]*) status_value=;; esac
  if printf '%s\n' "$status_value" | grep -Eq '^Rescanning source pane\.\.\.$|^Rescanned: [0-9]+ issues$|^(No Jira keys found|Source terminal unavailable|Could not read source terminal); keeping previous [0-9]+$'; then printf '%s\n' "$status_value"; fi
}
if [ "${1:-}" = rescan-start ]; then
  status_tmp=$(mktemp "$state/.status.XXXXXX") || exit 1
  printf '%s\n' 'Rescanning source pane...' > "$status_tmp"
  mv "$status_tmp" "$state/status"
  set -- header
fi
if [ "${1:-}" = header ]; then
  if [ -e "$state/ui-help" ]; then
     printf 'Up/Down choose \302\267 Type filters\nEnter full issue (q back) \302\267 Esc close\nPgUp/PgDn or Ctrl-D/U scroll preview\nCtrl-O browser \302\267 Ctrl-Y copy key \302\267 Ctrl-L copy link\nCtrl-G rescan \302\267 Ctrl-R refresh \302\267 F1 compact filter\n'
  elif [ "${VIEWER_HAS_FOOTER:-0}" = 0 ]; then
    if [ -s "$state/ui-message" ]; then
       printf '%s \302\267 F1 Help \302\267 Esc Close\n' "$(sed -n '1p' "$state/ui-message")"
    else
       printf 'Enter Read \302\267 Ctrl-G Rescan \302\267 F1 Help \302\267 Esc Close\n'
    fi
  fi
  status_line
  exit 0
fi
if [ "${1:-}" = prompt ]; then
  printf 'Filter > '
  exit 0
fi
if [ "${1:-}" = footer ]; then
  cols=${FZF_COLUMNS:-${COLUMNS:-80}}
  case "$cols" in ''|*[!0-9]*) cols=80;; esac
  [ -s "$state/ui-message" ] && sed -n '1p' "$state/ui-message"
   if [ "$cols" -lt 48 ]; then printf 'F1 Help \302\267 Esc Close';
   elif [ "$cols" -lt 70 ]; then printf 'Enter Read \302\267 Ctrl-G Rescan \302\267 F1 Help \302\267 Esc Close';
   else printf 'Enter Read \302\267 Ctrl-G Rescan \302\267 PgUp/PgDn Scroll \302\267 F1 Help \302\267 Esc Close'; fi
  exit 0
fi
if [ "${1:-}" = help ]; then
  if [ -e "$state/ui-help" ]; then rm -f "$state/ui-help"; else : > "$state/ui-help"; fi
   sh "$DIR/viewer-rows.sh" header
  exit 0
fi
if [ "${1:-}" = status ]; then
  status_line
  exit 0
fi
# Chrome reads only viewer-owned UI state. Initialize the full runtime only
# when building issue rows, never to paint a prompt, header, or shortcut bar.
. "$DIR/common.sh"
mkdir -p "$state/failed"
if [ "${1:-}" = snapshot ]; then out=$2; else out=; fi
tmp=$(mktemp "$state/.snapshot.XXXXXX") || exit 1
trap 'rm -f "$tmp"' 0 1 2 15
candidate_count=0
key_width=$(awk 'length($0) > n { n=length($0) } END { if (n < 7) n=7; print n }' "$CANDIDATES_FILE")
while IFS= read -r key || [ -n "$key" ]; do
  validate_key "$key" || continue
  candidate_count=$((candidate_count + 1))
  row=$state/rows/$key
  if [ -s "$row" ]; then
      awk -F '\t' -v reset="${VIEWER_RESET:-}" \
      -v dim="${VIEWER_DIM:-}" -v green="${VIEWER_GREEN:-}" \
      -v yellow="${VIEWER_YELLOW:-}" -v red="${VIEWER_RED:-}" \
      -v kw="$key_width" 'function clip(s,n) { if (length(s) <= n) return s; if (s ~ /[^ -~]/) return s; return substr(s,1,n-3) "..." } { k=$1; s=clip($2,18); l=tolower($2); c=dim; if (l ~ /^(done|closed|resolved)/) c=green; else if (l ~ /(progress|review|qa|testing)/) c=yellow; else if (l ~ /(block|hold)/) c=red; printf "%s\t%-*s  %s%-18s%s  %s%s\n",k,kw,k,c,s,reset,$3,reset }' "$row"
  else
    placeholder='fetching...'
    [ "$candidate_count" -le "$MAX_CANDIDATES" ] || placeholder='preview on select'
    printf '%s\t%-*s  %s%-18s%s\n' "$key" "$key_width" "$key" "${VIEWER_DIM:-}" "$placeholder" "${VIEWER_RESET:-}"
  fi
done < "$CANDIDATES_FILE" > "$tmp"
if [ -n "$out" ]; then mv "$tmp" "$out"; else cat "$tmp"; rm -f "$tmp"; fi
trap - 0 1 2 15
