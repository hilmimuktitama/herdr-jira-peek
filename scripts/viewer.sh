#!/bin/sh
# shellcheck disable=SC2016,SC2209,SC1007,SC2329 # fzf callbacks are literal commands; traps/functions are indirect.
# shellcheck source=scripts/common.sh
# Adjacent split pane: one fzf screen. List and issue preview share the space;
# everything else is a keybinding. Enter reads full-screen and returns here; Esc closes.
set -eu
. "$(dirname "$0")/common.sh"
DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
export DIR
# fzf binds from the private viewer directory; child scripts still need stable
# absolute state/config paths when the caller supplied relative paths.
STATE=$(CDPATH= cd "$STATE" && pwd)
CONFIG_DIR=$(CDPATH= cd "$CONFIG_DIR" && pwd)
HANDOFF_STATE_DIR=$(CDPATH= cd "$HANDOFF_STATE_DIR" && pwd)
export HERDR_PLUGIN_STATE_DIR="$STATE" HERDR_PLUGIN_CONFIG_DIR="$CONFIG_DIR"

viewer_state=$(mktemp -d "$HANDOFF_STATE_DIR/.viewer.$$.XXXXXX") || die 'could not create viewer state'
viewer_cleanup_early() { rm -rf "$viewer_state"; }
viewer_signal_early() { viewer_cleanup_early; trap - 0; exit 1; }
trap viewer_cleanup_early 0
trap viewer_signal_early 1 2 15
mkdir "$viewer_state/rows" "$viewer_state/failed" || die 'could not create viewer state'
candidate_seed=$CANDIDATES_FILE
export VIEWER_STATE_DIR="$viewer_state"
CANDIDATES_FILE="$viewer_state/candidates"
if [ -n "${HERDR_VIEWER_CANDIDATES+x}" ]; then printf '%s\n' "$HERDR_VIEWER_CANDIDATES" > "$CANDIDATES_FILE"; else cp "$candidate_seed" "$CANDIDATES_FILE" 2>/dev/null || true; fi
if [ ! -s "$CANDIDATES_FILE" ]; then
  if [ -s "$KEY_FILE" ]; then
    key=$(sed -n '1p' "$KEY_FILE")
    save_key "$key"
    candidate_tmp=$(mktemp "$viewer_state/.candidates.XXXXXX") || die 'could not create candidate list'
    printf '%s\n' "$key" > "$candidate_tmp"
    mv "$candidate_tmp" "$CANDIDATES_FILE"
  else
    die 'no issue candidates'
  fi
fi

# State can outlive the process that created it. Keep only complete, safe keys.
clean_candidates=$(mktemp "$viewer_state/.candidates.XXXXXX") || die 'could not create candidate list'
candidate_count=0
while IFS= read -r key || [ -n "$key" ]; do
  if validate_key "$key" && [ "$candidate_count" -lt "$MAX_CANDIDATES" ]; then
    duplicate=0
    grep -Fqx "$key" "$clean_candidates" 2>/dev/null && duplicate=1 || true
    if [ "$duplicate" -eq 0 ]; then
      printf '%s\n' "$key" >> "$clean_candidates"
      candidate_count=$((candidate_count + 1))
    fi
  fi
done < "$CANDIDATES_FILE"
if [ ! -s "$clean_candidates" ]; then
  die 'no valid issue candidates'
fi
mv "$clean_candidates" "$CANDIDATES_FILE"

n=$(wc -l < "$CANDIDATES_FILE" | tr -d ' ')

basic_menu() {
  reason=${1:-}; selected=1
  read_issue_with_pager() {
    key=$1
    sh "$DIR/viewer-reader.sh" "$DIR" "$key"
  }
  read_issue() {
    key=$(sed -n "${selected}p" "$CANDIDATES_FILE"); save_key "$key"
    if ! read_issue_with_pager "$key"; then
      printf 'Could not render %s; press Enter for the menu.\n' "$key"
      IFS= read -r _ || true
    fi
  }
  while :; do
    printf '\nJira Peek: %s issue(s)' "$n"; [ -n "$reason" ] && printf ' (picker unavailable: %s)' "$reason"; printf '\n'
    i=1; while IFS= read -r key; do marker=' '; [ "$i" -eq "$selected" ] && marker='>'; printf '%s%s) %s\n' "$marker" "$i" "$key"; i=$((i+1)); done < "$CANDIDATES_FILE"
    selected_key=$(sed -n "${selected}p" "$CANDIDATES_FILE")
    printf 'Selected %s (%s/%s)\n' "$selected_key" "$selected" "$n"
    printf 'Number/exact key or Enter reads.\n'
     printf 'n/p next/previous, r refreshes selected, s rescans, q closes.\n'
     printf 'Commands need Enter. Reader: q back · ↑↓ scroll · Space/b page.\n> '
    IFS= read -r choice || return 0
    case "$choice" in
      q|Q) return 0;; n|N) selected=$((selected % n + 1));; p|P) selected=$(( (selected + n - 2) % n + 1));;
       r|R) key=$(sed -n "${selected}p" "$CANDIDATES_FILE"); printf 'Refreshing %s...\n' "$key"; rm -f "$CACHE/$key.json"; clear_fetch_error "$key" || true; read_issue;;
       s|S)
         old_key=$(sed -n "${selected}p" "$CANDIDATES_FILE")
         sh "$DIR/viewer-rescan.sh" >/dev/null 2>&1 || true
         n=$(wc -l < "$CANDIDATES_FILE" | tr -d ' ')
         sh "$DIR/viewer-rows.sh" status
         selected=$(awk -v k="$old_key" '$0 == k { print NR; exit }' "$CANDIDATES_FILE")
         [ -n "$selected" ] || { [ "$n" -gt 0 ] && selected=1; }
         ;;
      '' ) read_issue;;
      *) index=$(awk -v choice="$choice" '($0 == choice) || (choice ~ /^[0-9]+$/ && choice + 0 == NR) { print NR; exit }' "$CANDIDATES_FILE"); [ -n "$index" ] || { printf 'Unknown issue.\n'; continue; }; selected=$index; read_issue;;
    esac
  done
}

# fzf is optional; the basic menu must not start metadata workers.
unset VIEWER_METADATA_MODE VIEWER_COORDINATOR_PID
if ! command -v fzf >/dev/null 2>&1; then
  basic_menu 'fzf is not installed'
  exit 0
fi

# Prepare an initial snapshot, then load a capped metadata batch. Full issue
# detail is fetched lazily when selected for preview or reading.
if [ -n "${NO_COLOR:-}" ]; then
  printf '  loading %s issue(s) from Jira...\n' "$n"
else
  printf '\033[2m  loading %s issue(s) from Jira...\033[0m\n' "$n"
fi
unset FZF_API_KEY
stop_tree() {
  p=$1; expected=$2
  case "$p" in ''|*[!0-9]*) return 0;; esac
  case "$expected" in ''|*[!0-9]*) return 0;; esac
  parent=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); [ "$parent" = "$expected" ] || return 0
  kill -STOP "$p" 2>/dev/null || true
  ps -e -o pid= -o ppid= 2>/dev/null | awk -v parent="$p" '$2 == parent { print $1 }' | while read -r child; do ( stop_tree "$child" "$p" ); done
  kill -CONT "$p" 2>/dev/null || true; kill -TERM "$p" 2>/dev/null || true
}
viewer_cleanup() {
  if [ -n "${viewer_workers:-}" ]; then
    stop_tree "$viewer_workers" "$$" || true
    wait "$viewer_workers" 2>/dev/null || true
  fi
  rm -rf "$viewer_state"
}
trap viewer_cleanup 0 1 2 15
viewer_signal() { viewer_cleanup; trap - 0; exit 1; }
trap viewer_signal 1 2 15

# Row = KEY<TAB>display. fzf shows the display and hands scripts the key as {1}.
if [ -n "${NO_COLOR:-}" ]; then
  bold=
  reset=
  dim=
  green=
  yellow=
  red=
else
  bold=$(printf '\033[1m')
  reset=$(printf '\033[0m')
  dim=$(printf '\033[2m')
  green=$(printf '\033[32m')
  yellow=$(printf '\033[33m')
  red=$(printf '\033[31m')
fi
export VIEWER_BOLD="$bold" VIEWER_RESET="$reset" VIEWER_DIM="$dim" VIEWER_GREEN="$green" VIEWER_YELLOW="$yellow" VIEWER_RED="$red"
sh "$DIR/viewer-rows.sh" snapshot "$viewer_state/snapshot"
fzf_help=$(env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -u FZF_DEFAULT_OPTS_FILE fzf --help 2>&1 || true)
if printf '%s\n' "$fzf_help" | grep -q -- '--footer'; then modernfooter=1; else modernfooter=0; fi
export VIEWER_MODERN_FOOTER=$modernfooter
export VIEWER_HAS_FOOTER=$modernfooter
if printf '%s\n' "$fzf_help" | grep -q -- '--id-nth' \
  && printf '%s\n' "$fzf_help" | grep -q -- '--track'; then
  fzf_tracking=1
else
  fzf_tracking=0
fi
if command -v curl >/dev/null 2>&1 \
  && printf '%s\n' "$fzf_help" | grep -q -- '--listen-unsafe' \
  && printf '%s\n' "$fzf_help" | grep -q -- '--id-nth' \
  && [ "$fzf_tracking" -eq 1 ]; then
  live_fzf=1
  VIEWER_METADATA_MODE=live
  mkdir "$viewer_state/pending-refresh"
  viewer_socket=fzf.sock
  export VIEWER_FZF_SOCKET="$viewer_socket"
    sh "$DIR/viewer-fetch.sh" --watch >/dev/null 2>&1 &
    viewer_workers=$!
    export VIEWER_COORDINATOR_PID=$viewer_workers
    ready=0; i=0
    while [ "$i" -lt 100 ]; do
      kill -0 "$viewer_workers" 2>/dev/null || break
      [ -e "$viewer_state/coordinator-ready" ] && { ready=1; break; }
      sleep 0.02; i=$((i + 1))
    done
    if [ "$ready" -ne 1 ]; then
      stop_tree "$viewer_workers" "$$" || true; wait "$viewer_workers" 2>/dev/null || true
      viewer_workers=; unset VIEWER_COORDINATOR_PID VIEWER_FZF_SOCKET
      live_fzf=0; VIEWER_METADATA_MODE=batch; VIEWER_NOTIFY=0 sh "$DIR/viewer-fetch.sh" --all >/dev/null 2>&1 || true
      sh "$DIR/viewer-rows.sh" snapshot "$viewer_state/snapshot"
    else
      request_tmp=$(mktemp "$viewer_state/.snapshot.XXXXXX")
      cp "$CANDIDATES_FILE" "$request_tmp"; mv "$request_tmp" "$viewer_state/pending-snapshot"
    fi
  rows=$viewer_state/snapshot
else
  live_fzf=0
  VIEWER_METADATA_MODE=batch
  VIEWER_NOTIFY=0 sh "$DIR/viewer-fetch.sh" --all >/dev/null 2>&1 || true
  rows=$viewer_state/snapshot
  sh "$DIR/viewer-rows.sh" snapshot "$rows"
fi
export VIEWER_METADATA_MODE
input_file=$rows

# Reserve chrome, the compact navigator, and a little breathing room for the
# preview. Unlike --height this remains correct when fzf owns the full PTY.
preview_window=$(VIEWER_STATE_DIR="$viewer_state" FZF_COLUMNS="${FZF_COLUMNS:-${COLUMNS:-80}}" sh "$DIR/viewer-ui.sh" layout "$n")
: > "$viewer_state/ui-layout"
printf '%s\n' "$preview_window" > "$viewer_state/ui-layout"

# These commands are evaluated by fzf after it expands its placeholders.
header=$(sh "$DIR/viewer-rows.sh" header)
prompt=$(sh "$DIR/viewer-rows.sh" prompt)
footer=$(sh "$DIR/viewer-rows.sh" footer)
run_fzf() {
  if [ -n "${NO_COLOR:-}" ]; then
    env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -u FZF_DEFAULT_OPTS_FILE fzf --no-color "$@"
  else
    env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -u FZF_DEFAULT_OPTS_FILE fzf "$@"
  fi
}
run_picker() {
  if [ "$live_fzf" -eq 1 ]; then
    (cd "$viewer_state" && run_fzf "$@" --id-nth 1 --track --listen-unsafe="$viewer_socket")
  elif [ "$fzf_tracking" -eq 1 ]; then
    run_fzf "$@" --id-nth 1 --track
  else
    run_fzf "$@"
  fi
}
run_picker_chrome() {
  set -- "$@"
  if [ -n "$footer_args" ]; then
    set -- "$@" --footer "$footer" --footer-border=none
  fi
  [ -n "${info_arg:-}" ] && set -- "$@" --info-command "$info_arg"
  [ -n "${highlight_arg:-}" ] && set -- "$@" "$highlight_arg" --no-bold
  [ -n "${gutter_arg:-}" ] && set -- "$@" --gutter ' '
  [ -n "${resize_binding:-}" ] && set -- "$@" --bind "$resize_binding"
  run_picker "$@"
}
if [ "$VIEWER_METADATA_MODE" = live ]; then
  refresh_binding='ctrl-r:execute-silent(sh "$DIR/viewer-fetch.sh" --queue-refresh {1})'
else
  refresh_binding='ctrl-r:execute-silent(VIEWER_NOTIFY=0 sh "$DIR/viewer-fetch.sh" --refresh {1})+reload(sh "$DIR/viewer-rows.sh")+refresh-preview'
fi
footer_args=
info_arg=
highlight_arg=
gutter_arg=
help_binding='f1:transform-header(sh "$DIR/viewer-rows.sh" help)'
copy_key_binding='ctrl-y:transform-header(sh "$DIR/viewer-ui.sh" copy-key {1})'
copy_link_binding='ctrl-l:transform-header(sh "$DIR/viewer-ui.sh" copy-link {1})'
open_binding='ctrl-o:transform-header(sh "$DIR/viewer-ui.sh" open {1})'
if printf '%s\n' "$fzf_help" | grep -q -- '--footer'; then footer_args="--footer=$footer"; fi
if [ "$modernfooter" -eq 1 ]; then
  copy_key_binding='ctrl-y:transform-footer(sh "$DIR/viewer-ui.sh" copy-key {1})+transform(sh "$DIR/viewer-ui.sh" relayout)'
  copy_link_binding='ctrl-l:transform-footer(sh "$DIR/viewer-ui.sh" copy-link {1})+transform(sh "$DIR/viewer-ui.sh" relayout)'
  open_binding='ctrl-o:transform-footer(sh "$DIR/viewer-ui.sh" open {1})+transform(sh "$DIR/viewer-ui.sh" relayout)'
fi
printf '%s\n' "$fzf_help" | grep -q -- '--info-command' && info_arg='printf "%s/%s" "${FZF_MATCH_COUNT:-0}" "${FZF_TOTAL_COUNT:-0}"'
printf '%s\n' "$fzf_help" | grep -q -- '--highlight-line' && highlight_arg=--highlight-line
printf '%s\n' "$fzf_help" | grep -q -- '--gutter' && gutter_arg=1
if [ "$modernfooter" -eq 1 ]; then
  help_binding='f1:transform(sh "$DIR/viewer-ui.sh" help)'
fi
load_binding='load:transform-header(sh "$DIR/viewer-rows.sh" header)+transform-prompt(sh "$DIR/viewer-rows.sh" prompt)+refresh-preview'
resize_binding=
if [ "$modernfooter" -eq 1 ]; then
  load_binding='load:transform-header(sh "$DIR/viewer-rows.sh" header)+transform-prompt(sh "$DIR/viewer-rows.sh" prompt)+refresh-preview+transform(sh "$DIR/viewer-ui.sh" relayout)'
  resize_binding='resize:transform-footer(sh "$DIR/viewer-rows.sh" footer)+transform(sh "$DIR/viewer-ui.sh" relayout)+refresh-preview'
fi
fzf_status=0
# shellcheck disable=SC2016
if run_picker_chrome \
  --ansi --cycle --layout=reverse --info=inline-right --no-separator --border=none \
  --delimiter '\t' --with-nth 2 \
   --prompt "$prompt" --pointer '>' \
  --header "$header" \
  --header-first \
  --preview 'sh "$DIR/viewer-preview.sh" {1} 2>&1' \
  --preview-window "$preview_window" \
  --preview-label ' issue ' \
   --bind 'enter:execute(sh "$DIR/viewer-reader.sh" "$DIR" {1} >/dev/tty 2>/dev/tty)' \
  --bind "$open_binding" \
  --bind "$copy_key_binding" \
  --bind "$copy_link_binding" \
   --bind "$refresh_binding" \
   --bind 'ctrl-g:execute-silent(sh "$DIR/viewer-rescan.sh")+reload(sh "$DIR/viewer-rows.sh")' \
   --bind "$load_binding" \
  --bind "$help_binding" \
  --bind 'pgdn:preview-page-down,pgup:preview-page-up,ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up' \
  --bind 'focus:change-preview-label( issue )+execute-silent(sh "$DIR/open-browser.sh" --select {1})' \
  --bind 'esc:abort' \
  < "$input_file" > /dev/null 2> "$viewer_state/fzf-stderr"; then
  :
else
  fzf_status=$?
fi
case "$fzf_status" in
  0|1|130)
    exit 0
    ;;
  2)
    reason=$(sanitize_fetch_error_file "$viewer_state/fzf-stderr" 2>/dev/null || true)
    [ -n "$reason" ] || reason='fzf startup failed'
    if [ -n "${viewer_workers:-}" ]; then
      stop_tree "$viewer_workers" "$$" || true
      wait "$viewer_workers" 2>/dev/null || true
      viewer_workers=
    fi
    unset VIEWER_FZF_SOCKET
    unset VIEWER_METADATA_MODE VIEWER_COORDINATOR_PID VIEWER_FZF_SOCKET
    basic_menu "$reason"
    exit 0
    ;;
  *)
    exit "$fzf_status"
    ;;
esac
