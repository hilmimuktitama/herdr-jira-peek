#!/bin/sh
# Full-screen issue reader. Kept in its own process so its traps cannot replace
# the viewer's cleanup traps.
set -eu
DIR=$1
key=$2

restore_cursor() { [ -t 1 ] && tput cnorm 2>/dev/null || true; }
trap restore_cursor 0
trap 'exit 1' 1 2 15
[ -t 1 ] && tput civis 2>/dev/null || true

# Short issues must start at the top, even when less inherits the bottom
# cursor position from fzf. -c repaints from the top instead of scrolling.
unset FZF_PREVIEW_COLUMNS
if command -v less >/dev/null 2>&1; then
  pager_style=; pager_reset=
  if [ -z "${NO_COLOR:-}" ] && [ "${TEXT_STYLE:-bold}" = bold ]; then
    pager_style=$(printf '\033[2m'); pager_reset=$(printf '\033[0m')
  fi
  {
    printf 'Issue details\n\n'
    sh "$DIR/render.sh" "$key" 2>&1
  } | LESS_TERMCAP_so="$pager_style" LESS_TERMCAP_se="$pager_reset" \
    less -c -R -~ -P 'q back · ↑↓ scroll · Space/b page'
else
  printf 'Issue details\n\n'
  sh "$DIR/render.sh" "$key" 2>&1
fi
