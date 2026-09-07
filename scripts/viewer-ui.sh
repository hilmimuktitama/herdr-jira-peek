#!/bin/sh
# Small fzf action dispatcher; keeps command results in the stable footer.
set -eu
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
kind=${1:-}; key=${2:-}
if [ "$kind" = layout ]; then
  dimensions() {
    value=$1; fallback=$2
    case "$value" in ''|0*|*[!0-9]*) value=$fallback;; esac
    printf '%s' "$value"
  }
  cols=$(dimensions "${FZF_COLUMNS:-${COLUMNS:-}}" 0)
  rows=$(dimensions "${FZF_LINES:-${LINES:-}}" 0)
  [ "$cols" -gt 0 ] || cols=$(dimensions "$(tput cols 2>/dev/null || true)" 80)
  [ "$rows" -gt 0 ] || rows=$(dimensions "$(tput lines 2>/dev/null || true)" 24)
  count=${2:-}
  if [ -z "$count" ] && [ -n "${VIEWER_STATE_DIR:-}" ]; then count=$(awk 'NF {n++} END {print n+0}' "$VIEWER_STATE_DIR/candidates" 2>/dev/null || printf 0); fi
  case "$count" in ''|*[!0-9]*) count=1;; esac
  nav=$count; [ "$rows" -ge 45 ] && [ "$nav" -gt 10 ] && nav=10; [ "$rows" -lt 45 ] && [ "$nav" -gt 8 ] && nav=8
  header_lines=0; [ "${VIEWER_HAS_FOOTER:-0}" = 0 ] && header_lines=1
  [ -e "${VIEWER_STATE_DIR:-}/ui-help" ] && header_lines=5
  status_lines=0; [ -s "${VIEWER_STATE_DIR:-}/status" ] && status_lines=1
  footer_lines=0
  if [ "${VIEWER_HAS_FOOTER:-0}" = 1 ]; then
    footer_lines=1; [ -s "${VIEWER_STATE_DIR:-}/ui-message" ] && footer_lines=2
  fi
  budget=$((rows - nav - 1 - header_lines - status_lines - footer_lines - 1))
  if [ "$cols" -ge 160 ] && [ "$rows" -ge 20 ]; then
    printf 'right,62%%,wrap,border-left,nohidden'
  elif [ "$budget" -ge 4 ]; then
    printf 'down,%s,wrap,border-top,nohidden' "$budget"
  else
    printf 'hidden'
  fi
  exit 0
fi
if [ "$kind" = relayout ]; then
  layout=$(VIEWER_STATE_DIR="${VIEWER_STATE_DIR:-}" sh "$DIR/viewer-ui.sh" layout)
  previous=$(sed -n '1p' "${VIEWER_STATE_DIR:-}/ui-layout" 2>/dev/null || true)
  if [ "$layout" != "$previous" ]; then
    printf '%s\n' "$layout" > "${VIEWER_STATE_DIR:-}/ui-layout"
    printf 'change-preview-window(%s)' "$layout"
  fi
  exit 0
fi
if [ "$kind" = help ]; then
  header=$(sh "$DIR/viewer-rows.sh" help)
  relayout=$(VIEWER_STATE_DIR="${VIEWER_STATE_DIR:-}" sh "$DIR/viewer-ui.sh" relayout)
  if [ -n "$relayout" ]; then printf '%s+' "$relayout"; fi
  printf 'change-header[%s]' "$header"
  exit 0
fi
case "$kind" in
  copy-key) action=--copy-key; success='Copied key'; failure='Could not copy key' ;;
  copy-link) action=--copy-link; success='Copied link'; failure='Could not copy link' ;;
  open) action=--key; success='Opened browser'; failure='Could not open browser' ;;
  *) exit 2 ;;
esac
if sh "$DIR/open-browser.sh" "$action" "$key" >/dev/null 2>&1; then
  printf '%s\n' "$success" > "$VIEWER_STATE_DIR/ui-message"
else
  printf '%s\n' "$failure" > "$VIEWER_STATE_DIR/ui-message"
fi
if [ "${VIEWER_MODERN_FOOTER:-0}" = 1 ]; then
  sh "$DIR/viewer-rows.sh" footer
else
  sh "$DIR/viewer-rows.sh" header
fi
