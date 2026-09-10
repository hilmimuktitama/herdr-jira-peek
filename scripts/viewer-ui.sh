#!/bin/sh
# Small fzf action dispatcher; shows temporary action feedback in the footer.
# shellcheck disable=SC2016 # Commands sent to fzf are evaluated in its environment.
set -eu
DIR=${DIR:-$(CDPATH='' cd "${0%/*}" && pwd)}
kind=${1:-}; key=${2:-}
if [ "$kind" = queue-rescan ]; then
  # Only enqueue on fzf's input loop. The viewer-owned worker survives resize
  # background transforms and keeps Herdr reads/configuration off this path.
  [ ! -e "$VIEWER_STATE_DIR/rescan-busy" ] || exit 0
  : > "$VIEWER_STATE_DIR/rescan-busy"
  header=$(sh "$DIR/viewer-rows.sh" rescan-start)
  : > "$VIEWER_STATE_DIR/pending-rescan"
  printf 'change-header[%s]' "$header"
  exit 0
fi
if [ "$kind" = focus ]; then
  # The viewer has already validated config, scoped the key file, and built
  # its candidate list. Navigation must not reload config or sweep caches.
  if [ -n "$key" ]; then
    case "$key" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*) exit 1;; esac
    grep -Fqx -- "$key" "$VIEWER_STATE_DIR/candidates" || exit 1
    selected_file=${VIEWER_KEY_FILE:?}
    current_key=
    if [ -f "$selected_file" ] && [ ! -L "$selected_file" ]; then IFS= read -r current_key < "$selected_file" || true; fi
    if [ "$current_key" != "$key" ]; then
      umask 077
      key_tmp=$(mktemp "${selected_file%/*}/.key.XXXXXX") || exit 1
      if ! { printf '%s\n' "$key" > "$key_tmp" && mv "$key_tmp" "$selected_file"; }; then
        rm -f "$key_tmp"; exit 1
      fi
    fi
  fi
  kind=dismiss-message
fi
message_expired() {
  expiry=$(sed -n '2p' "$VIEWER_STATE_DIR/ui-message" 2>/dev/null || true)
  case "$expiry" in ''|*[!0-9]*) return 1;; esac
  [ "$(date +%s)" -ge "$expiry" ]
}
if [ "$kind" = watch-messages ]; then
  # Independent of Jira fetches and fzf background rescans. Only the fzf
  # event loop clears feedback, so a queued expiry cannot erase a newer one.
  cd "$VIEWER_STATE_DIR"
  while [ -d "$VIEWER_STATE_DIR" ]; do
    if [ -s "$VIEWER_STATE_DIR/ui-message" ] && [ -S "$VIEWER_FZF_SOCKET" ] && message_expired; then
      curl -sS --max-time 1 --unix-socket "$VIEWER_FZF_SOCKET" -X POST http://localhost \
        -d 'transform(sh "$DIR/viewer-ui.sh" expire-message)' >/dev/null 2>&1 || true
    fi
    sleep 0.25
  done
  exit 0
fi
if [ "$kind" = expire-message ] || [ "$kind" = dismiss-message ]; then
  [ -s "$VIEWER_STATE_DIR/ui-message" ] || exit 0
  if [ "$kind" = expire-message ]; then message_expired || exit 0; fi
  rm -f "$VIEWER_STATE_DIR/ui-message"
  if [ "${VIEWER_MODERN_FOOTER:-0}" = 1 ]; then
    printf 'change-footer[%s]' "$(sh "$DIR/viewer-rows.sh" footer)"
    relayout=$(sh "$DIR/viewer-ui.sh" relayout)
    [ -z "$relayout" ] || printf '+%s' "$relayout"
  else
    printf 'change-header[%s]' "$(sh "$DIR/viewer-rows.sh" header)"
  fi
  exit 0
fi
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
  if [ "${VIEWER_PICKER_LAYOUT:-bottom}" = bottom ]; then
    if [ "$budget" -ge 4 ]; then
      printf 'up,%s,wrap,border-bottom,nohidden' "$budget"
    else
      printf 'hidden'
    fi
  elif [ "$cols" -ge 160 ] && [ "$rows" -ge 20 ]; then
    printf 'right,62%%,wrap,border-left,nohidden'
  elif [ "$budget" -ge 4 ]; then
    printf 'down,%s,wrap,border-top,nohidden' "$budget"
  else
    printf 'hidden'
  fi
  exit 0
fi
if [ "$kind" = resize ]; then
  footer=$(sh "$DIR/viewer-rows.sh" footer)
  relayout=$(sh "$DIR/viewer-ui.sh" relayout)
  printf 'change-footer[%s]+%s+refresh-preview' "$footer" "$relayout"
  exit 0
fi
if [ "$kind" = relayout ]; then
  layout=$(VIEWER_STATE_DIR="${VIEWER_STATE_DIR:-}" sh "$DIR/viewer-ui.sh" layout)
  # This file records requested layout for diagnostics, not applied fzf state.
  # Background results can be canceled, so let fzf deduplicate layout changes.
  printf '%s\n' "$layout" > "${VIEWER_STATE_DIR:-}/ui-layout"
  printf 'change-preview-window(%s)' "$layout"
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
  message=$success; duration=3
else
  message=$failure; duration=6
fi
message_tmp=$(mktemp "$VIEWER_STATE_DIR/.ui-message.XXXXXX")
printf '%s\n%s\n' "$message" "$(( $(date +%s) + duration ))" > "$message_tmp"
mv "$message_tmp" "$VIEWER_STATE_DIR/ui-message"
if [ "${VIEWER_MODERN_FOOTER:-0}" = 1 ]; then
  sh "$DIR/viewer-rows.sh" footer
else
  sh "$DIR/viewer-rows.sh" header
fi
