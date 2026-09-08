#!/bin/sh
# shellcheck disable=SC2015,SC2016,SC2089,SC2090,SC2034,SC1007,SC2046,SC2155,SC2012 # Generated fixtures and intentional mode inspection are test-only.
# Dependency-free smoke tests for the runtime scripts. TWG and Herdr are faked.
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TEST_TMPDIR=${TMPDIR:-/tmp}
while [ "$TEST_TMPDIR" != "/" ] \
  && [ "${TEST_TMPDIR%/}" != "$TEST_TMPDIR" ]; do
  TEST_TMPDIR=${TEST_TMPDIR%/}
done
TMP=$(mktemp -d "$TEST_TMPDIR/jira-peek-tests.XXXXXX")
trap '[ "${KEEP_TEST_TMP:-}" = 1 ] || rm -rf "$TMP"' 0 1 2 15
BIN="$TMP/bin"
CONFIG="$TMP/config"
STATE="$TMP/state"
mkdir -p "$BIN" "$CONFIG" "$STATE"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

( . "$ROOT/config.example.sh" ) || fail 'sourceable public config example'
ORIGINAL_PATH=$PATH
REAL_FZF_PATH=$(command -v fzf 2>/dev/null || true)
REAL_LESS_PATH=$(command -v less 2>/dev/null || true)
case "$REAL_FZF_PATH" in
  /*) [ -x "$REAL_FZF_PATH" ] || REAL_FZF_PATH='' ;;
  *) REAL_FZF_PATH='' ;;
esac

# Setup and dependency installation use isolated fake CLIs.
sh "$ROOT/tests/dependencies.sh"

# Doctor reports actionable checks without echoing the config or TWG response.
DOCTOR_CONFIG="$TMP/doctor-config"
DOCTOR_STATE="$TMP/doctor-state"
DOCTOR_BIN="$TMP/doctor-bin"
mkdir -p "$DOCTOR_CONFIG"
mkdir -p "$DOCTOR_BIN"
chmod 700 "$DOCTOR_CONFIG" "$DOCTOR_BIN"
printf '%s\n' '#!/bin/sh' \
  'if [ "${1:-}" = --version ]; then printf "%s\n" "twg version 1.2.6"; exit 0; fi' \
  'exit 17' > "$DOCTOR_BIN/twg"
chmod 700 "$DOCTOR_BIN/twg"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  'CACHE_TTL_MIN=10' \
  'MAX_CANDIDATES=20' \
  > "$DOCTOR_CONFIG/config.sh"
if ! doctor_output=$(env PATH="$DOCTOR_BIN:$ORIGINAL_PATH" \
  HERDR_PLUGIN_CONFIG_DIR="$DOCTOR_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$DOCTOR_STATE" TWG_ACCESS_MODE=fail \
  sh "$ROOT/scripts/doctor.sh" 2>&1); then
  :
else
  fail 'doctor surfaces unauthenticated TWG'
fi
case "$doctor_output" in
  *'FAIL TWG is not authenticated or not configured'* ) pass 'doctor diagnostics' ;;
  *) fail 'doctor diagnostics' ;;
esac
case "$doctor_output" in
  *jira-example*|*jira.example.test*|*TWG\ response*|*\{*) fail 'doctor does not leak config or response data' ;;
esac

# Both runtime and doctor parse config.sh as a fixed set of data assignments;
# shell syntax inside a value must never execute.
MALICIOUS_CONFIG="$TMP/malicious-config"
MALICIOUS_STATE="$TMP/malicious-state"
MALICIOUS_MARKER="$TMP/config-was-executed"
mkdir -p "$MALICIOUS_CONFIG" "$MALICIOUS_STATE"
chmod 700 "$MALICIOUS_CONFIG" "$MALICIOUS_STATE"
printf 'JIRA_BASE="$(touch %s)"\n' "$MALICIOUS_MARKER" > "$MALICIOUS_CONFIG/config.sh"
printf '%s\n' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC"' \
  'CACHE_TTL_MIN=10' \
  'MAX_CANDIDATES=20' \
  >> "$MALICIOUS_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$MALICIOUS_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$MALICIOUS_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'runtime rejects shell syntax in config values'
fi
[ ! -e "$MALICIOUS_MARKER" ] || fail 'runtime executed config shell syntax'
if env PATH="$DOCTOR_BIN:$ORIGINAL_PATH" \
  HERDR_PLUGIN_CONFIG_DIR="$MALICIOUS_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$MALICIOUS_STATE" \
  sh "$ROOT/scripts/doctor.sh" >/dev/null 2>&1; then
  fail 'doctor rejects shell syntax in config values'
fi
[ ! -e "$MALICIOUS_MARKER" ] || fail 'doctor executed config shell syntax'
pass 'config is parsed as data, never executed'

SYMLINK_CONFIG="$TMP/symlink-config"
SYMLINK_STATE="$TMP/symlink-state"
mkdir -p "$SYMLINK_CONFIG" "$SYMLINK_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC"' \
  > "$TMP/real-config.sh"
ln -s "$TMP/real-config.sh" "$SYMLINK_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$SYMLINK_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$SYMLINK_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'runtime rejects symlinked config'
fi
pass 'runtime rejects symlinked config'

# clear-cache removes direct cache payload/temp files only, preserving session
# handoff/diagnostic state and nested unrelated files.
CLEAR_STATE="$TMP/clear-state"
mkdir -p "$CLEAR_STATE/cache/nested" "$CLEAR_STATE/fetch-errors"
printf '%s\n' issue > "$CLEAR_STATE/cache/ABC-123.json"
printf '%s\n' temp > "$CLEAR_STATE/cache/.raw.XXXXXX"
printf '%s\n' nested > "$CLEAR_STATE/cache/nested/keep"
printf '%s\n' ABC-123 > "$CLEAR_STATE/key"
printf '%s\n' stale > "$CLEAR_STATE/fetch-errors/fetch-error-ABC-123"
if ! env HERDR_PLUGIN_STATE_DIR="$CLEAR_STATE" \
  sh "$ROOT/scripts/clear-cache.sh" >/dev/null; then
  fail 'clear-cache succeeds'
fi
[ ! -e "$CLEAR_STATE/cache/ABC-123.json" ] \
  && [ ! -e "$CLEAR_STATE/cache/.raw.XXXXXX" ] \
  || fail 'clear-cache removes direct cache files'
[ -e "$CLEAR_STATE/cache/nested/keep" ] \
  || fail 'clear-cache preserves nested state'
[ -e "$CLEAR_STATE/key" ] && [ -e "$CLEAR_STATE/fetch-errors/fetch-error-ABC-123" ] \
  || fail 'clear-cache preserves plugin state'
pass 'clear-cache scope'

write_fake() {
  name=$1
  shift
  printf '%s\n' "$@" > "$BIN/$name"
  chmod 700 "$BIN/$name"
}

write_fake twg \
  '#!/bin/sh' \
  'printf "%s\n" "$*" >> "$TWG_LOG"' \
  'printf "%s\n" "${JIRA_SITE:-}" >> "$TWG_SITE_LOG"' \
  'if [ "${1:-}" = --help ]; then' \
  '  printf "%s\n" "twg jira workitem get KEY --comments --output json"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" = --version ]; then' \
  '  printf "%s\n" "twg version 1.2.6"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" = doctor ]; then' \
  '  [ "${TWG_DOCTOR_MODE:-ok}" = ok ] || exit 17' \
  '  printf "%s\n" "{\"ok\":true}"' \
  '  exit 0' \
  'fi' \
  'if [ "${1:-}" = --site ] && [ "${3:-}" = access ]; then' \
  '  [ "${TWG_ACCESS_MODE:-ok}" = ok ] || exit 17' \
  '  printf "%s\n" "{\"ok\":true}"' \
  '  exit 0' \
  'fi' \
  'if [ "${TWG_MODE:-}" = nonzero ]; then' \
  '  printf "%s" "${TWG_STDERR:-TWG command failed}" >&2' \
  '  exit 17' \
  'fi' \
  'if [ "${TWG_MODE:-}" = race ]; then' \
  '  if [ "${TWG_RACE_ROLE:-}" = success ]; then' \
  '    : > "$TWG_RACE_SUCCESS_STARTED"' \
  '    while [ ! -f "$TWG_RACE_SUCCESS_RELEASE" ]; do sleep 1; done' \
  '    printf "%s\n" "{\"key\":\"ABC-123\"}"' \
  '    exit 0' \
  '  fi' \
  '  if [ "${TWG_RACE_ROLE:-}" = failure ]; then' \
  '    : > "$TWG_RACE_FAILURE_STARTED"' \
  '    while [ ! -f "$TWG_RACE_FAILURE_RELEASE" ]; do sleep 1; done' \
  '    printf "%s" "late race failure" >&2' \
  '    exit 17' \
  '  fi' \
  'fi' \
  'if [ "${TWG_MODE:-}" = json-nonzero ]; then' \
  '  printf "%s\n" "$TWG_JSON"' \
  '  printf "%s" "${TWG_STDERR:-}" >&2' \
  '  exit 17' \
  'fi' \
   'if [ "${TWG_MODE:-}" = raw-issue ]; then' \
   '  printf "%s\n" "{\"key\":\"ABC-123\",\"summary\":\"Portable peek\",\"status\":{\"name\":\"Done\"}}"' \
   '  exit 0' \
   'fi' \
   'if [ "${TWG_MODE:-}" = refresh-success ]; then' \
   '  printf "%s\n" "{\"key\":\"ABC-123\",\"summary\":\"new refresh\",\"status\":{\"name\":\"Done\"}}"' \
   '  exit 0' \
   'fi' \
   'if [ "${TWG_MODE:-}" = data-object ]; then' \
   '  printf "%s\n" "{\"data\":{\"key\":\"ABC-123\",\"summary\":\"Portable peek\",\"status\":{\"name\":\"Done\"}}}"; exit 0' \
   'fi' \
   'if [ "${TWG_MODE:-}" = wrong-array ]; then' \
   '  printf "%s\n" "{\"data\":[{\"key\":\"DEF-9\"}]}"; exit 0' \
   'fi' \
   'if [ "${TWG_MODE:-}" = multiple-array ]; then' \
   '  printf "%s\n" "{\"data\":[{\"key\":\"ABC-123\"},{\"key\":\"DEF-9\"}]}"; exit 0' \
   'fi' \
  'case " $* " in *" --output json jira workitem get "*" --fields summary,status,assignee,updated "*)' \
   '  printf "%s\n" "{\"apiVersion\":\"v2\",\"command\":\"jira.workitem.get\",\"data\":{\"items\":[{\"input\":\"ABC-123\",\"ok\":true,\"data\":{\"key\":\"ABC-123\",\"summary\":\"Portable peek\",\"status\":{\"name\":\"Done\"}}},{\"input\":\"DEF-9\",\"ok\":true,\"data\":{\"key\":\"DEF-9\",\"summary\":\"Other issue\",\"status\":{\"name\":\"To Do\"}}}],\"summary\":{}}}"' \
  '  exit 0' \
  'esac' \
  'case " $* " in *" --output json jira workitem get ABC-123 --comments "*)' \
   '  printf "%s\n" "{\"apiVersion\":\"v2\",\"command\":\"jira workitem get\",\"data\":[{\"key\":\"ABC-123\",\"summary\":\"Portable peek\",\"description\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Description text\"}]}]},\"status\":{\"name\":\"Done\"},\"assignee\":{\"displayName\":\"Ada Lovelace\"},\"updated\":\"2026-09-03T12:34:56Z\",\"url\":\"https://jira.example.test/browse/ABC-123?from=twg\",\"comments\":[{\"author\":{\"displayName\":\"Reviewer\"},\"created\":\"2026-09-03T13:00:00Z\",\"body\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Looks good\"}]}]}}]}],\"meta\":{},\"request\":{}}"' \
  '  exit 0' \
  'esac' \
  exit 1

write_fake herdr \
  '#!/bin/sh' \
  'logged=$(printf "%s" "$*" | tr "\\n" " "); printf "%s\\n" "$logged" >> "$HERDR_LOG"' \
  'if [ "$1" = pane ] && [ "$2" = read ]; then' \
  '  printf "%s\n" "$1 $2 $3 $4 $5" >> "$HERDR_SOURCE_LOG"' \
  '  case "${5:-}" in' \
  '    visible) text=${HERDR_VISIBLE_TEXT-${HERDR_READ_TEXT:-older ABC-123 then DEF-9}} ;;' \
  '    recent-unwrapped) text=${HERDR_RECENT_TEXT-${HERDR_READ_TEXT:-older ABC-123 then DEF-9}} ;;' \
  '    detection) text=${HERDR_DETECTION_TEXT-${HERDR_READ_TEXT:-older ABC-123 then DEF-9}} ;;' \
  '    *) text=${HERDR_READ_TEXT:-older ABC-123 then DEF-9} ;;' \
  '  esac' \
  '  printf "%s\n" "$text"' \
  '  exit 0' \
  'fi' \
'if [ "$1" = pane ] && [ "$2" = get ]; then' \
  '  requested=$3' \
  '  case "$requested" in focused-pane|link-source-pane) printf "%s\n" "{\"result\":{\"pane\":{\"pane_id\":\"$requested\",\"terminal_id\":\"terminal-source\"}}}"; exit 0;; esac' \
  '  row=$(awk -F "\t" -v requested="$requested" '\''$1 == requested { print; exit }'\'' "$HERDR_LIVE_PANES")' \
  '  [ -n "$row" ] || exit 1' \
  '  pane_id=$(printf "%s\\n" "$row" | cut -f1); terminal_id=$(printf "%s\\n" "$row" | cut -f2)' \
  '  printf "%s\n" "{\"result\":{\"pane\":{\"pane_id\":\"$pane_id\",\"terminal_id\":\"$terminal_id\"}}}"' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = workspace ] && [ "$2" = list ]; then' \
  '  printf "%s\n" "{\"result\":{\"workspaces\":[{\"workspace_id\":\"workspace-a\"},{\"workspace_id\":\"workspace-b\"}]}}"' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = pane ] && [ "$2" = list ]; then' \
  '  awk -F "\t" -v workspace="$4" '\''BEGIN { printf "{\"result\":{\"panes\":["; first=1 } $3 == workspace { if (!first) printf ","; printf "{\"pane_id\":\"%s\",\"terminal_id\":\"%s\"}", $1, $2; first=0 } END { print "]}}" }'\'' "$HERDR_LIVE_PANES"' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = plugin ] && [ "$2" = pane ] && [ "$3" = open ]; then' \
  '  count=0' \
  '  [ -s "$HERDR_OPEN_COUNT" ] && count=$(sed -n "1p" "$HERDR_OPEN_COUNT")' \
  '  count=$((count + 1))' \
  '  printf "%s\n" "$count" > "$HERDR_OPEN_COUNT"' \
  '  pane_id="viewer-pane-$count"' \
  '  terminal_id="terminal-$count"' \
  '  printf "%s\t%s\t%s\n" "$pane_id" "$terminal_id" workspace-a >> "$HERDR_LIVE_PANES"' \
  '  if [ -n "${HERDR_OPEN_GATE:-}" ] && [ ! -f "$HERDR_OPEN_RELEASE" ]; then' \
  '    : > "$HERDR_OPEN_STARTED"' \
  '    while [ ! -f "$HERDR_OPEN_RELEASE" ]; do sleep 1; done' \
  '  fi' \
  '  printf "%s\n" "{\"result\":{\"plugin_pane\":{\"pane\":{\"pane_id\":\"$pane_id\",\"terminal_id\":\"$terminal_id\"}}}}"' \
  '  exit 0' \
  'fi' \
  'if [ "$1" = plugin ] && [ "$2" = pane ] && [ "$3" = close ]; then' \
  '  if [ "${HERDR_CLOSE_FAIL_PANE:-}" = "$4" ]; then' \
  '    exit 1' \
  '  fi' \
  '  if awk -F "\t" -v requested="$4" '\''$1 == requested { found=1 } END { exit !found }'\'' "$HERDR_LIVE_PANES"; then' \
  '    tmp="$HERDR_LIVE_PANES.tmp"' \
  '    awk -F "\t" -v requested="$4" '\''$1 != requested'\'' "$HERDR_LIVE_PANES" > "$tmp"' \
  '    mv "$tmp" "$HERDR_LIVE_PANES"' \
  '    exit 0' \
  '  fi' \
  '  exit 1' \
  'fi'

write_fake uname \
  '#!/bin/sh' \
  'printf "%s\n" "${FAKE_UNAME:-Darwin}"'

write_fake open \
  '#!/bin/sh' \
  'printf "%s\n" "$1" > "$OPEN_LOG"'

write_fake xdg-open \
  '#!/bin/sh' \
  'printf "%s\n" "$1" > "$OPEN_LOG"'

write_fake fzf \
  '#!/bin/sh' \
  'printf "%s\n" "$1:${FZF_DEFAULT_OPTS+x}:${FZF_DEFAULT_COMMAND+x}:${FZF_DEFAULT_OPTS_FILE+x}" >> "$FZF_ENV_LOG"' \
  '[ -z "${FZF_DEFAULT_OPTS+x}" ] && [ -z "${FZF_DEFAULT_COMMAND+x}" ] && [ -z "${FZF_DEFAULT_OPTS_FILE+x}" ] || exit 97' \
  'if [ "$1" = --help ]; then' \
  '  if [ "${FZF_OLD_MODE:-}" = 1 ]; then printf "%s\n" "--header --preview-window --bind"; else printf "%s\n" "--footer --info-command --highlight-line --header --preview-window --bind"; fi' \
  '  exit 0' \
  'fi' \
  ': > "$FZF_ARGS_LOG"' \
  'for arg do printf "%s\n" "$arg" >> "$FZF_ARGS_LOG"; done' \
  'cat > "$FZF_INPUT_LOG"' \
  '[ -n "${FZF_STDERR:-}" ] && printf "%s\n" "$FZF_STDERR" >&2' \
  'if [ -n "${FZF_EXIT_STATUS:-}" ]; then exit "$FZF_EXIT_STATUS"; fi'

write_fake less \
  '#!/bin/sh' \
  'printf "%s\n" "$@" > "$LESS_ARGS_LOG"' \
  'printf "%s\n" "so=${LESS_TERMCAP_so-}" "se=${LESS_TERMCAP_se-}" > "$LESS_ENV_LOG"' \
  'tee "$LESS_INPUT_LOG"'

write_fake pbcopy \
  '#!/bin/sh' \
  'cat > "$COPY_LOG"'

write_fake wl-copy \
  '#!/bin/sh' \
  'cat > "$COPY_LOG"'

printf '%s\n' \
  'JIRA_BASE="https://jira.example.test/"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  'CACHE_TTL_MIN=10' \
  > "$CONFIG/config.sh"

export PATH="$BIN:$PATH"
export HERDR_PLUGIN_CONFIG_DIR="$CONFIG"
export HERDR_PLUGIN_STATE_DIR="$STATE"
export HERDR_PLUGIN_ID=jira-peek
export TWG_LOG="$TMP/twg.log"
export TWG_SITE_LOG="$TMP/twg-site.log"
export HERDR_LOG="$TMP/herdr.log"
export HERDR_LIVE_PANES="$TMP/live-panes"
export HERDR_OPEN_COUNT="$TMP/open-count"
export HERDR_OPEN_GATE=
export HERDR_OPEN_STARTED="$TMP/open-started"
export HERDR_OPEN_RELEASE="$TMP/open-release"
export HERDR_CLOSE_FAIL_PANE=
export OPEN_LOG="$TMP/open.log"
export COPY_LOG="$TMP/copy.log"
export FZF_ARGS_LOG="$TMP/fzf-args.log"
export FZF_ENV_LOG="$TMP/fzf-env.log"
export FZF_INPUT_LOG="$TMP/fzf-input.log"
export FZF_EXIT_STATUS=
export HERDR_READ_TEXT=
unset HERDR_VISIBLE_TEXT HERDR_RECENT_TEXT HERDR_DETECTION_TEXT
export HERDR_SOURCE_LOG="$TMP/herdr-sources.log"
export LESS_ARGS_LOG="$TMP/less-args.log"
export LESS_INPUT_LOG="$TMP/less-input.log"
export LESS_ENV_LOG="$TMP/less-env.log"
export HERDR_BIN_PATH=herdr
export TWG_RACE_SUCCESS_STARTED="$TMP/race-success-started"
export TWG_RACE_SUCCESS_RELEASE="$TMP/race-success-release"
export TWG_RACE_FAILURE_STARTED="$TMP/race-failure-started"
export TWG_RACE_FAILURE_RELEASE="$TMP/race-failure-release"
unset HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_PLUGIN_CONTEXT_JSON TWG_MODE TWG_STDERR TWG_JSON \
  NO_COLOR FZF_PREVIEW_COLUMNS

# Pinned, auth-free TWG contract smoke: the plugin relies on direct JSON
# output, comments, and no summary-envelope flag.
if ! twg --help 2>/dev/null | grep -Fqx 'twg jira workitem get KEY --comments --output json'; then
  fail 'TWG help contract'
fi
pass 'TWG help contract (auth-free)'
: > "$TWG_LOG"
: > "$TWG_SITE_LOG"

run_with_state() {
  test_config=$1
  test_state=$2
  shift 2
  env -u TMPDIR HERDR_PLUGIN_CONFIG_DIR="$test_config" HERDR_PLUGIN_STATE_DIR="$test_state" "$@"
}

run() {
  env -u TMPDIR HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$STATE" "$@"
}

strip_plugin_ansi() {
  esc=$(printf '\033')
  printf '%s' "$1" \
    | sed "s/${esc}\\[1m//g; s/${esc}\\[36m//g; s/${esc}\\[0m//g"
}

strip_picker_ansi() {
  esc=$(printf '\033')
  printf '%s' "$1" | sed "s/${esc}\\[[0-9;]*m//g"
}

session_dir() {
  session_id=$(printf '%s' "$1" | cksum | awk '{print $1}')
  printf '%s/session-%s' "$STATE" "$session_id"
}

if ! output=$(run sh "$ROOT/scripts/fetch.sh" ABC-123); then
  fail 'valid TWG fetch'
fi
expected=$(printf 'ABC-123\tDone\tPortable peek')
[ "$output" = "$expected" ] && pass 'valid TWG fetch' || fail 'valid TWG fetch output'
[ -s "$STATE/cache/ABC-123.json" ] || fail 'canonical issue cached'
jq -e 'type == "object" and .key == "ABC-123" and (has("data") | not) and (has("meta") | not)' \
  "$STATE/cache/ABC-123.json" >/dev/null || fail 'canonical cache excludes envelope'
expected_call='--mode user --api-version v2 --site jira-example --output json jira workitem get ABC-123 --comments'
[ "$(sed -n '1p' "$TWG_LOG")" = "$expected_call" ] || fail 'exact TWG fetch command'
pass 'exact TWG fetch command'
[ "$(sed -n '1p' "$TWG_LOG")" = "$expected_call" ] \
  || fail 'JIRA_SITE forwarded to TWG'
pass 'JIRA_SITE forwarded to TWG'

if ! output=$(run sh "$ROOT/scripts/fetch.sh" ABC-123); then
  fail 'fresh cache fetch'
fi
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = 1 ] || fail 'fresh cache avoids TWG'
pass 'fresh cache avoids TWG'

# The public fetch contract is a single JSON document on stdout. There is no
# YAML summary envelope or caller-controlled temporary payload to discover.
RAW_JSON_CONFIG="$TMP/raw-json-config"
RAW_JSON_STATE="$TMP/raw-json-state"
mkdir -p "$RAW_JSON_CONFIG" "$RAW_JSON_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  'CACHE_TTL_MIN=10' \
  > "$RAW_JSON_CONFIG/config.sh"
raw_json_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
if ! raw_json_output=$(env HERDR_PLUGIN_CONFIG_DIR="$RAW_JSON_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$RAW_JSON_STATE" TWG_MODE=raw-issue \
  sh "$ROOT/scripts/fetch.sh" ABC-123); then
  fail 'pure JSON TWG fetch'
fi
raw_json_expected=$(printf 'ABC-123\tDone\tPortable peek')
[ "$raw_json_output" = "$raw_json_expected" ] \
  || fail 'pure JSON TWG fetch row output'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$((raw_json_before + 1))" ] \
  || fail 'pure JSON TWG fetch invoked once'
[ ! -e "$RAW_JSON_STATE/cache/.raw" ] \
  || fail 'pure JSON fetch left a durable raw temp file'
pass 'pure JSON TWG fetch without summary envelope'

data_object_state="$TMP/data-object-state"
mkdir -p "$data_object_state"
if ! env HERDR_PLUGIN_CONFIG_DIR="$RAW_JSON_CONFIG" HERDR_PLUGIN_STATE_DIR="$data_object_state" \
  TWG_MODE=data-object sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null; then
  fail 'data-object wrapper fetch'
fi
pass 'data-object wrapper fetch'

for invalid_mode in wrong-array multiple-array; do
  invalid_state="$TMP/invalid-$invalid_mode"
  mkdir -p "$invalid_state"
  if env HERDR_PLUGIN_CONFIG_DIR="$RAW_JSON_CONFIG" HERDR_PLUGIN_STATE_DIR="$invalid_state" \
    TWG_MODE="$invalid_mode" sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
    fail "$invalid_mode response rejected"
  fi
  [ ! -e "$invalid_state/cache/ABC-123.json" ] || fail "$invalid_mode response cached"
done
pass 'wrong-key and multiple-item data arrays rejected'

BATCH_METADATA="$TMP/batch-metadata.json"
printf '%s\n' '{"data":{"items":[{"input":"ABC-123","ok":true,"data":{"key":"ABC-123","summary":"Portable peek","status":{"name":"Done"}}},{"input":"DEF-9","ok":true,"data":{"key":"DEF-9","summary":"Other issue","status":{"name":"To Do"}}},{"input":"GHI-7","ok":false,"data":{"key":"GHI-7"}},{"input":"JKL-2","ok":true},{"input":"MNO-4","ok":true,"data":{"key":"WRONG-1"}},{"input":"PQR-5","ok":true,"data":[]},{"input":"STU-6","ok":true,"data":"bad"},"malformed",[]],"summary":{}}}' > "$BATCH_METADATA"
if ! batch_rows=$(run sh -c '. "$1/scripts/common.sh"; metadata_row "$2" ABC-123; metadata_row "$2" DEF-9' sh "$ROOT" "$BATCH_METADATA"); then
  fail 'batch metadata loads successful entries'
fi
batch_expected=$(printf 'ABC-123\tDone\tPortable peek\nDEF-9\tTo Do\tOther issue')
[ "$batch_rows" = "$batch_expected" ] || fail 'batch metadata loads successful entries'
for batch_key in GHI-7 JKL-2 MNO-4 PQR-5 STU-6; do
  if run sh -c '. "$1/scripts/common.sh"; metadata_row "$2" "$3"' sh "$ROOT" "$BATCH_METADATA" "$batch_key" >/dev/null; then
    fail "batch metadata rejects $batch_key"
  fi
done
pass 'batch metadata filters unsuccessful and invalid entries'

DIAG_CONFIG="$TMP/diag-config"
DIAG_STATE="$TMP/diag-state"
mkdir -p "$DIAG_CONFIG" "$DIAG_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  'CACHE_TTL_MIN=10' \
  > "$DIAG_CONFIG/config.sh"

diag_file="$DIAG_STATE/fetch-errors/fetch-error-DEF-9"

export TWG_MODE=nonzero
export TWG_STDERR='plugin pane request denied'
if diag_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'TWG failure renders a diagnostic'
fi
case "$diag_output" in
  *'TWG could not read DEF-9: Jira request failed'*)
    pass 'TWG failure diagnostic is displayed' ;;
  *) fail 'TWG failure diagnostic is displayed' ;;
esac
[ -s "$diag_file" ] || fail 'TWG failure diagnostic is retained'
if grep -Fq 'plugin pane request denied' "$diag_file"; then fail 'raw diagnostic was persisted'; fi
printf '%s\n' 'email person@example.com confidential-project opaque upstream failure' > "$diag_file"
run_with_state "$DIAG_CONFIG" "$DIAG_STATE" sh -c '. "$1/scripts/common.sh"' legacy "$ROOT" \
  || fail 'legacy diagnostic purge startup'
[ ! -e "$diag_file" ] || fail 'legacy diagnostic was not purged before fetch'
legacy_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" sh "$ROOT/scripts/render.sh" DEF-9 2>&1 || true)
case "$legacy_output" in *email*|*confidential-project*|*opaque*|*upstream*) fail 'legacy diagnostic leaked' ;; esac
grep -Fqx 'Jira request failed' "$diag_file" || fail 'legacy diagnostic fixed category'
pass 'diagnostics retain only fixed local categories'

# Startup cleanup covers global and real session diagnostic state, validates
# complete bytes, and never follows a symlinked session directory.
PRIVACY_STATE="$TMP/privacy-state"
PRIVACY_CONFIG="$TMP/privacy-config"
PRIVACY_EXTERNAL="$TMP/privacy-external"
mkdir -p "$PRIVACY_CONFIG" "$PRIVACY_STATE/fetch-errors" "$PRIVACY_STATE/session-old/fetch-errors" "$PRIVACY_EXTERNAL"
cp "$DIAG_CONFIG/config.sh" "$PRIVACY_CONFIG/config.sh"
printf '%s\n' 'email person@example.com confidential-project opaque upstream text' > "$PRIVACY_STATE/fetch-errors/fetch-error-ABC-123"
printf '%s\n' 'email old@example.com confidential opaque' > "$PRIVACY_STATE/session-old/fetch-errors/fetch-error-DEF-9"
printf '%s\n' 'Jira request failed' > "$PRIVACY_STATE/fetch-errors/fetch-error-GHI-7"
{ printf '%s\n' 'Jira request failed'; printf '%s' 'opaque tail'; } > "$PRIVACY_STATE/fetch-errors/fetch-error-JKL-2"
if ! env HERDR_PLUGIN_CONFIG_DIR="$PRIVACY_CONFIG" HERDR_PLUGIN_STATE_DIR="$PRIVACY_STATE" \
  sh -c '. "$1/scripts/common.sh"' privacy "$ROOT" >/dev/null 2>&1; then
  fail 'normal diagnostic purge startup'
fi
[ ! -e "$PRIVACY_STATE/fetch-errors/fetch-error-ABC-123" ] || fail 'global raw diagnostic purge'
[ ! -e "$PRIVACY_STATE/session-old/fetch-errors/fetch-error-DEF-9" ] || fail 'session raw diagnostic purge'
printf '%s\n' 'Jira request failed' | cmp -s - "$PRIVACY_STATE/fetch-errors/fetch-error-GHI-7" \
  || fail 'fixed diagnostic retention'
[ ! -e "$PRIVACY_STATE/fetch-errors/fetch-error-JKL-2" ] || fail 'unterminated diagnostic tail purge'
mkdir -p "$PRIVACY_EXTERNAL/fetch-errors"
printf '%s\n' 'external raw sentinel' > "$PRIVACY_EXTERNAL/fetch-errors/fetch-error-MNO-4"
ln -s "$PRIVACY_EXTERNAL" "$PRIVACY_STATE/session-linked"
if env HERDR_SOCKET_PATH=privacy-current HERDR_PLUGIN_CONFIG_DIR="$PRIVACY_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$PRIVACY_STATE" sh -c '. "$1/scripts/common.sh"' privacy "$ROOT" >/dev/null 2>&1; then
  fail 'symlinked session was accepted'
fi
[ -f "$PRIVACY_EXTERNAL/fetch-errors/fetch-error-MNO-4" ] || fail 'symlink target was modified'
grep -Fqx 'external raw sentinel' "$PRIVACY_EXTERNAL/fetch-errors/fetch-error-MNO-4" \
  || fail 'symlink target contents changed'
pass 'diagnostic privacy cleanup covers global sessions and symlinks'

export TWG_MODE=json-nonzero
export TWG_JSON='{"error":{"message":"machine mode token=super-secret /tmp/private"}}'
export TWG_STDERR=
if diag_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'nonzero JSON failure renders a diagnostic'
fi
case "$diag_output" in
  *'TWG could not read DEF-9: Jira request failed'*)
    pass 'nonzero JSON failure diagnostic is displayed' ;;
  *) fail "nonzero JSON failure diagnostic is displayed: $diag_output" ;;
esac
case "$diag_output" in
  *super-secret*|*/tmp/private*|*'{"error"'*) fail 'nonzero JSON failure content leaked' ;;
esac
pass 'nonzero JSON failure is redacted without stderr'

export TWG_MODE=nonzero
export TWG_STDERR='password="alpha beta gamma"'
if quoted_secret_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'quoted multiword credential remains a failure'
fi
case "$quoted_secret_output" in
  *alpha*|*beta*|*gamma*|*password*) fail 'quoted multiword credential leaked' ;;
  *) pass 'quoted multiword credential is fully redacted' ;;
 esac
 export TWG_MODE=nonzero
export TWG_STDERR=$(printf 'pane \033[31m token=secret /tmp/private\nsecond line')
if diag_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'unsafe TWG diagnostic remains a failure'
fi
case "$diag_output" in
  *'TWG could not read DEF-9: Jira request failed'*)
    pass 'safe TWG diagnostic is displayed' ;;
  *) fail "safe TWG diagnostic is displayed: $diag_output" ;;
esac
esc=$(printf '\033')
case "$diag_output" in *"$esc"*|*second*|*secret*|*/tmp/private*) fail 'unsafe TWG diagnostic content leaked' ;; esac
diagnostic_lines=$(printf '%s\n' "$diag_output" | wc -l | tr -d ' ')
[ "$diagnostic_lines" = 1 ] || fail 'unsafe TWG diagnostic is a single line'
pass 'unsafe TWG diagnostic content is sanitized'

export TWG_MODE=nonzero
export TWG_STDERR='client_secret = abc.def'
SPACED_SECRET_STATE="$TMP/spaced-secret-state"
if spaced_secret_output=$(run_with_state "$DIAG_CONFIG" "$SPACED_SECRET_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'credential-like TWG diagnostic remains a failure'
fi
case "$spaced_secret_output" in
  *'TWG could not read DEF-9: Jira request failed'*) : ;;
  *) fail 'spaced credential diagnostic is redacted' ;;
esac
case "$spaced_secret_output" in
  *abc.def*|*client_secret*) fail 'spaced credential diagnostic leaked' ;;
esac
pass 'spaced credential diagnostics are redacted'

for credential_text in "SECRET='alpha beta gamma'" 'MiXeD_CrEdEnTiAl="alpha beta gamma"' 'Bearer alpha beta' 'Cookie session=abc' 'API KEY = abc'; do
  export TWG_STDERR="$credential_text"
  if credential_output=$(run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
    sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
    fail 'case-variant quoted credential remains a failure'
  fi
  case "$credential_output" in
    *alpha*|*beta*|*gamma*|*SECRET*|*MiXeD*) fail 'case-variant quoted credential leaked' ;;
    *) : ;;
  esac
done
pass 'case-variant quoted credentials are rejected'

# A generic Jira authorization failure is not evidence that the TWG client
# itself lacks credentials; preserve that distinction in remediation text.
export TWG_STDERR='Authentication required for Jira project ABC'
JIRA_AUTH_STATE="$TMP/jira-auth-state"
if jira_auth_output=$(run_with_state "$DIAG_CONFIG" "$JIRA_AUTH_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'Jira authorization failure remains a failure'
fi
case "$jira_auth_output" in
  *'Jira request failed'*) : ;;
  *) fail 'Jira authorization failure classification' ;;
esac
case "$jira_auth_output" in
  *'TWG is not authenticated'*) fail 'Jira authorization failure mislabeled as TWG auth' ;;
esac
[ -f "$JIRA_AUTH_STATE/fetch-errors/fetch-error-DEF-9" ] \
  && ! grep -Fq 'Authentication required for Jira project ABC' "$JIRA_AUTH_STATE/fetch-errors/fetch-error-DEF-9" \
  || fail 'Jira authorization raw text persisted'
pass 'Jira and TWG authentication failures stay distinct'

# Missing TWG and an installed-but-unauthenticated TWG are distinct operator
# failures; neither case may create an issue cache entry.
MISSING_TWG_STATE="$TMP/missing-twg-state"
mv "$BIN/twg" "$BIN/twg.fake"
if missing_twg_output=$(env PATH="$BIN:$ORIGINAL_PATH" \
  TWG_BIN_PATH="$TMP/no-such-twg" \
  HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" HERDR_PLUGIN_STATE_DIR="$MISSING_TWG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  mv "$BIN/twg.fake" "$BIN/twg"
  fail 'missing TWG remains a failure'
fi
mv "$BIN/twg.fake" "$BIN/twg"
case "$missing_twg_output" in
  *'TWG CLI unavailable'*) pass 'missing TWG diagnostic' ;;
  *) fail 'missing TWG diagnostic' ;;
esac
[ ! -e "$MISSING_TWG_STATE/cache/DEF-9.json" ] \
  || fail 'missing TWG did not avoid durable cache data'

export TWG_MODE=nonzero
export TWG_STDERR='not authenticated; run twg setup'
UNAUTH_TWG_STATE="$TMP/unauth-twg-state"
if unauth_twg_output=$(run_with_state "$DIAG_CONFIG" "$UNAUTH_TWG_STATE" \
  sh "$ROOT/scripts/render.sh" DEF-9 2>&1); then
  fail 'unauthenticated TWG remains a failure'
fi
case "$unauth_twg_output" in
  *'TWG is not authenticated or configured; run twg setup, then retry'*)
    pass 'unauthenticated TWG diagnostic' ;;
  *) fail 'unauthenticated TWG diagnostic' ;;
esac
[ ! -e "$UNAUTH_TWG_STATE/cache/DEF-9.json" ] \
  || fail 'unauthenticated TWG did not avoid durable cache data'
pass 'TWG availability and authentication diagnostics'
export TWG_MODE=
export TWG_STDERR=

RACE_STATE="$TMP/race-state"
RACE_SUCCESS_OUTPUT="$TMP/race-success-output"
RACE_FAILURE_OUTPUT="$TMP/race-failure-output"
env -u TMPDIR \
  HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$RACE_STATE" \
  TWG_MODE=race TWG_RACE_ROLE=success \
  sh "$ROOT/scripts/fetch.sh" ABC-123 > "$RACE_SUCCESS_OUTPUT" 2>&1 &
race_success_pid=$!
race_wait=0
while [ ! -f "$TWG_RACE_SUCCESS_STARTED" ] && [ "$race_wait" -lt 10 ]; do
  sleep 1
  race_wait=$((race_wait + 1))
done
[ -f "$TWG_RACE_SUCCESS_STARTED" ] || fail 'race success fetch started'

env -u TMPDIR \
  HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$RACE_STATE" \
  TWG_MODE=race TWG_RACE_ROLE=failure \
  sh "$ROOT/scripts/fetch.sh" ABC-123 > "$RACE_FAILURE_OUTPUT" 2>&1 &
race_failure_pid=$!
race_wait=0
while [ ! -f "$TWG_RACE_FAILURE_STARTED" ] && [ "$race_wait" -lt 10 ]; do
  sleep 1
  race_wait=$((race_wait + 1))
done
[ -f "$TWG_RACE_FAILURE_STARTED" ] || fail 'race failure fetch started'
: > "$TWG_RACE_SUCCESS_RELEASE"
race_wait=0
while [ ! -s "$RACE_STATE/cache/ABC-123.json" ] && [ "$race_wait" -lt 10 ]; do
  sleep 1
  race_wait=$((race_wait + 1))
done
if ! jq -s -e 'length == 1 and ((.[0] | type) == "object") and .[0].key == "ABC-123"' \
  "$RACE_STATE/cache/ABC-123.json" >/dev/null 2>&1; then
  fail 'race success installed a valid cache'
fi
printf '%s\n' stale > "$RACE_STATE/fetch-errors/fetch-error-ABC-123"
: > "$TWG_RACE_FAILURE_RELEASE"
if ! wait "$race_success_pid"; then
  fail 'race success fetch completed'
fi
if ! wait "$race_failure_pid"; then
  fail 'race failure fetch completed'
fi
race_failure_output=$(sed -n '1p' "$RACE_FAILURE_OUTPUT")
case "$race_failure_output" in
  *'(could not load)'*) fail 'late same-key failure did not reuse cache' ;;
esac
jq -s -e 'length == 1 and ((.[0] | type) == "object") and .[0].key == "ABC-123"' \
  "$RACE_STATE/cache/ABC-123.json" >/dev/null \
  || fail 'late same-key failure preserved cache'
[ ! -e "$RACE_STATE/fetch-errors/fetch-error-ABC-123" ] \
  || fail 'late same-key failure cleared diagnostic'
pass 'same-key failure preserves concurrent cache and clears diagnostic'

# A refresh in another session invalidates the global generation while the old
# response is still held; the old response must not publish afterward.
TWO_SESSION_STATE="$TMP/two-session-state"
TWO_SESSION_STARTED="$TMP/two-session-old-started"
TWO_SESSION_RELEASE="$TMP/two-session-old-release"
TWO_SESSION_OLD_OUTPUT="$TMP/two-session-old-output"
mkdir -p "$TWO_SESSION_STATE"
env HERDR_SOCKET_PATH=session-a HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$TWO_SESSION_STATE" TWG_MODE=race TWG_RACE_ROLE=success \
  TWG_RACE_SUCCESS_STARTED="$TWO_SESSION_STARTED" TWG_RACE_SUCCESS_RELEASE="$TWO_SESSION_RELEASE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >"$TWO_SESSION_OLD_OUTPUT" 2>&1 &
two_session_pid=$!
race_wait=0
while [ ! -f "$TWO_SESSION_STARTED" ] && [ "$race_wait" -lt 10 ]; do sleep 1; race_wait=$((race_wait + 1)); done
[ -f "$TWO_SESSION_STARTED" ] || { kill "$two_session_pid" 2>/dev/null || true; fail 'two-session old response started'; }
env HERDR_SOCKET_PATH=session-b HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$TWO_SESSION_STATE" sh -c '. "$1/scripts/common.sh"; clear_cache ABC-123' \
  sh "$ROOT" || { : > "$TWO_SESSION_RELEASE"; wait "$two_session_pid" || true; fail 'two-session refresh invalidation'; }
env HERDR_SOCKET_PATH=session-b HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$TWO_SESSION_STATE" TWG_MODE=refresh-success \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'two-session new refresh fetch'
jq -e '.summary == "new refresh"' "$TWO_SESSION_STATE/cache/ABC-123.json" >/dev/null \
  || fail 'two-session new cache content'
: > "$TWO_SESSION_RELEASE"
if wait "$two_session_pid"; then fail 'old response was accepted after refresh'; fi
jq -e '.summary == "new refresh"' "$TWO_SESSION_STATE/cache/ABC-123.json" >/dev/null \
  || fail 'old response overwrote refreshed cache'
if grep -Fq 'Portable peek' "$TWO_SESSION_OLD_OUTPUT"; then fail 'old response exposed stale data'; fi
pass 'global generation blocks stale cross-session publication'

export TWG_MODE=
export TWG_STDERR=
export TWG_JSON=
printf '%s\n' stale > "$DIAG_STATE/fetch-errors/fetch-error-ABC-123"
if ! run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null; then
  fail 'successful TWG fetch clears its diagnostic'
fi
[ ! -e "$DIAG_STATE/fetch-errors/fetch-error-ABC-123" ] \
  || fail 'successful TWG fetch clears its diagnostic'
printf '%s\n' stale > "$DIAG_STATE/fetch-errors/fetch-error-ABC-123"
diag_twg_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
if ! run_with_state "$DIAG_CONFIG" "$DIAG_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null; then
  fail 'cache hit clears its diagnostic'
fi
[ ! -e "$DIAG_STATE/fetch-errors/fetch-error-ABC-123" ] \
  || fail 'cache hit clears its diagnostic'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$diag_twg_before" ] \
  || fail 'cache hit did not avoid TWG'
pass 'successful fetch and cache hit clear diagnostics'

ZERO_CONFIG="$TMP/zero-config"
ZERO_STATE="$TMP/zero-state"
mkdir -p "$ZERO_CONFIG" "$ZERO_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  'CACHE_TTL_MIN=0' \
  > "$ZERO_CONFIG/config.sh"
zero_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
env HERDR_PLUGIN_CONFIG_DIR="$ZERO_CONFIG" HERDR_PLUGIN_STATE_DIR="$ZERO_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'zero TTL initial fetch'
env HERDR_PLUGIN_CONFIG_DIR="$ZERO_CONFIG" HERDR_PLUGIN_STATE_DIR="$ZERO_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'zero TTL refetch'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$((zero_before + 2))" ] \
  || fail 'zero TTL reused cache'
twg_after_zero=$(wc -l < "$TWG_LOG" | tr -d ' ')
[ ! -e "$ZERO_STATE/cache/ABC-123.json" ] \
  || fail 'zero TTL left durable issue data'
if find "$ZERO_STATE" -type f -name '.issue-*' -print | grep -q .; then
  fail 'zero TTL left temporary issue data'
fi
pass 'zero TTL disables cache reuse and durable issue storage'

# PID-stamped work files survive only while their owner is alive. This closes
# the normal SIGKILL recovery gap without touching a concurrent fetch.
STALE_TEMP_CONFIG="$TMP/stale-temp-config"
STALE_TEMP_STATE="$TMP/stale-temp-state"
mkdir -p "$STALE_TEMP_CONFIG" "$STALE_TEMP_STATE/fetch-errors"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC"' \
  'CACHE_TTL_MIN=10' \
  > "$STALE_TEMP_CONFIG/config.sh"
printf '%s\n' abandoned > "$STALE_TEMP_STATE/.twg-json.99999999.stale"
printf '%s\n' abandoned > "$STALE_TEMP_STATE/.issue-ABC-123.99999999.stale"
printf '%s\n' abandoned > "$STALE_TEMP_STATE/fetch-errors/.fetch-error-ABC-123.99999999.stale"
printf '%s\n' active > "$STALE_TEMP_STATE/.twg-stderr.$$.active"
mkdir -p "$STALE_TEMP_STATE/.viewer.99999999.stale" "$STALE_TEMP_STATE/.viewer.$$.active"
printf '%s\n' abandoned > "$STALE_TEMP_STATE/.viewer.99999999.stale/metadata"
printf '%s\n' active > "$STALE_TEMP_STATE/.viewer.$$.active/metadata"
if ! env HERDR_PLUGIN_CONFIG_DIR="$STALE_TEMP_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$STALE_TEMP_STATE" \
  sh -c '. "$1/scripts/common.sh"' peek-test "$ROOT"; then
  fail 'abandoned fetch work cleanup'
fi
[ ! -e "$STALE_TEMP_STATE/.twg-json.99999999.stale" ] \
  && [ ! -e "$STALE_TEMP_STATE/.issue-ABC-123.99999999.stale" ] \
  && [ ! -e "$STALE_TEMP_STATE/fetch-errors/.fetch-error-ABC-123.99999999.stale" ] \
  && [ ! -e "$STALE_TEMP_STATE/.viewer.99999999.stale" ] \
  || fail 'abandoned fetch work was retained'
[ -e "$STALE_TEMP_STATE/.twg-stderr.$$.active" ] \
  || fail 'active fetch work was removed'
[ -e "$STALE_TEMP_STATE/.viewer.$$.active/metadata" ] \
  || fail 'active viewer state was removed'
rm -f "$STALE_TEMP_STATE/.twg-stderr.$$.active" \
  "$STALE_TEMP_STATE/.viewer.$$.active/metadata"
rmdir "$STALE_TEMP_STATE/.viewer.$$.active"
pass 'abandoned fetch and viewer work is reaped without touching active work'

# Cache purging remains flat: even TTL=0 cannot descend into unexpected nested
# state that may belong to another version or a user.
mkdir -p "$ZERO_STATE/cache/nested"
printf '%s\n' direct > "$ZERO_STATE/cache/direct.tmp"
printf '%s\n' nested > "$ZERO_STATE/cache/nested/keep"
env HERDR_PLUGIN_CONFIG_DIR="$ZERO_CONFIG" HERDR_PLUGIN_STATE_DIR="$ZERO_STATE" \
  sh -c '. "$1/scripts/common.sh"' peek-test "$ROOT" \
  || fail 'flat cache purge invocation'
[ ! -e "$ZERO_STATE/cache/direct.tmp" ] \
  && [ -e "$ZERO_STATE/cache/nested/keep" ] \
  || fail 'flat cache purge scope'
pass 'runtime cache purge preserves nested state'

# A stale entry is not just ignored: it is removed before a failed refresh so
# old issue content cannot survive indefinitely on disk.
EXPIRED_STATE="$TMP/expired-state"
mkdir -p "$EXPIRED_STATE/cache"
printf '%s\n' '{"key":"ABC-123","summary":"stale issue"}' \
  > "$EXPIRED_STATE/cache/ABC-123.json"
touch -t 200001010000 "$EXPIRED_STATE/cache/ABC-123.json"
export TWG_MODE=nonzero
export TWG_STDERR='offline'
if env HERDR_PLUGIN_CONFIG_DIR="$DIAG_CONFIG" HERDR_PLUGIN_STATE_DIR="$EXPIRED_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'expired cache failed refresh remains a failure'
fi
[ ! -e "$EXPIRED_STATE/cache/ABC-123.json" ] \
  || fail 'expired cache file was not deleted'
pass 'expired cache files are deleted'
export TWG_MODE=
export TWG_STDERR=

BAD_CONFIG="$TMP/bad-config"
BAD_STATE="$TMP/bad-state"
mkdir -p "$BAD_CONFIG" "$BAD_STATE"
printf '%s\n' \
  'JIRA_BASE="http://jira.example.test"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  > "$BAD_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$BAD_CONFIG" HERDR_PLUGIN_STATE_DIR="$BAD_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'HTTP JIRA_BASE rejected'
fi
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test/path"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  > "$BAD_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$BAD_CONFIG" HERDR_PLUGIN_STATE_DIR="$BAD_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'path-bearing JIRA_BASE rejected'
fi
pass 'JIRA_BASE requires a bare HTTPS origin'
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test "' \
  'JIRA_PROJECTS="ABC|DEF"' \
  > "$BAD_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$BAD_CONFIG" HERDR_PLUGIN_STATE_DIR="$BAD_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'whitespace JIRA_BASE rejected'
fi
pass 'whitespace JIRA_BASE rejected'
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test' \
  'newline"' \
  'JIRA_PROJECTS="ABC|DEF"' \
  > "$BAD_CONFIG/config.sh"
if env HERDR_PLUGIN_CONFIG_DIR="$BAD_CONFIG" HERDR_PLUGIN_STATE_DIR="$BAD_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null 2>&1; then
  fail 'multiline JIRA_BASE rejected'
fi
pass 'multiline JIRA_BASE rejected'

twg_before_render=$(wc -l < "$TWG_LOG" | tr -d ' ')
if ! output=$(run env COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'canonical cache rendering'
fi
case "$output" in
  *ABC-123*Done*Portable\ peek*Ada\ Lovelace*Updated*https://jira.example.test/browse/ABC-123\?from=twg*Description*Looks\ good*)
    pass 'canonical cache rendering' ;;
  *) fail 'canonical cache rendering output' ;;
esac
canonical_plain=$(strip_plugin_ansi "$output")
if printf '%s\n' "$canonical_plain" | awk '
   NR == 1 && $0 == "ABC-123 · Done" { first=1 }
   NR == 2 && $0 == "Portable peek" { title=1 }
   $0 == "Ada Lovelace · Updated 3 Sep 2026, 12:34 UTC" { assignee=1 }
   $0 == "UPDATED   2026-09-03T12:34:56Z" { updated=1 }
  $0 == "LINK      https://jira.example.test/browse/ABC-123?from=twg" { link=1 }
   END { exit !(first && title && assignee && updated && link) }
'; then
  pass 'render metadata is aligned and uppercase'
else
  fail 'render metadata is aligned and uppercase'
fi
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$twg_before_render" ] || fail 'render reused canonical cache'
pass 'render reused canonical cache'

printf '%s\n' '{"key":"ABC-123","summary":"A summary with a very long unbroken token Supercalifragilisticexpialidocious and useful words","status":{"name":"In Progress"},"assignee":{"displayName":"Ada Lovelace"},"updated":"2026-09-03T12:34:56Z","url":"https://jira.example.test/browse/ABC-123","description":{"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Overview"}]},{"type":"paragraph","content":[{"type":"text","text":"alpha beta gamma delta epsilon zeta eta theta iota kappa"},{"type":"hardBreak"},{"type":"text","text":"hard break survives"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"first list item"}]}]},{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"second list item"}]}]}]},{"type":"orderedList","attrs":{"order":1},"content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"ordered item"}]}]}]},{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"quoted text"}]}]},{"type":"codeBlock","content":[{"type":"text","text":"code one\n\ncode three"}]}]},"comments":[{"author":{"displayName":"Reviewer"},"created":"2026-09-03T13:00:00Z","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"comment text with enough words to wrap cleanly"}]}]}}]}' \
  > "$STATE/cache/ABC-123.json"
if ! complex_render=$(run env FZF_PREVIEW_COLUMNS=32 COLUMNS=200 \
  sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'ADF render and narrow wrapping'
fi
complex_plain=$(strip_plugin_ansi "$complex_render")
if printf '%s\n' "$complex_plain" | awk 'length($0) > 30 { bad=1 } END { exit bad }'; then
  pass 'rendered lines fit the preview width'
else
  fail 'rendered lines fit the preview width'
fi
case "$complex_plain" in
  *'## Overview'*'hard break survives'*'- first list item'*'1. ordered item'*'> quoted text'*'    code one'*'code three'*)
    pass 'ADF headings lists quotes and code stay readable' ;;
  *) fail 'ADF headings lists quotes and code stay readable' ;;
esac
compact_complex=$(printf '%s' "$complex_plain" | tr -d '\n')
case "$compact_complex" in
  *Supercalifragilisticexpialidocious*) pass 'long prose is wrapped without truncation' ;;
  *) fail 'long prose was truncated' ;;
esac
if printf '%s\n' "$complex_plain" | awk '
  $0 == "alpha beta gamma delta epsilon" { saw_first=1 }
  saw_first && $0 == "hard break survives" { saw_hard=1 }
  saw_hard && $0 == "" { saw_blank=1 }
  END { exit !(saw_first && saw_hard && saw_blank) }
'; then
  pass 'hard breaks and blank lines are preserved'
else
  fail 'hard breaks and blank lines are preserved'
fi

printf '%s\n' '{"key":"ABC-123","summary":"Unicode","description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22"}]}]}}' \
  > "$STATE/cache/ABC-123.json"
unicode_token=$(printf '%s\n' '"\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22\u6f22"' | jq -r .)
if ! unicode_render=$(run env FZF_PREVIEW_COLUMNS=12 COLUMNS=80 \
  sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'overlong Unicode render'
fi
unicode_plain=$(strip_plugin_ansi "$unicode_render")
if printf '%s\n' "$unicode_plain" | awk -v token="$unicode_token" \
  '$0 == token { found=1 } END { exit !found }'; then
  pass 'overlong Unicode tokens stay intact'
else
  fail 'overlong Unicode tokens were split'
fi

printf '%s\n' '{"key":"ABC-123","summary":"Unicode prefix","description":{"type":"doc","content":[{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"\u00e9\u00e9\u00e9\u6f22"}]}]}]}}' \
  > "$STATE/cache/ABC-123.json"
prefixed_unicode_token=$(printf '%s\n' '"\u00e9\u00e9\u00e9\u6f22"' | jq -r .)
if ! prefixed_unicode_render=$(run env FZF_PREVIEW_COLUMNS=12 COLUMNS=80 \
  sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'prefixed Unicode render'
fi
prefixed_unicode_plain=$(strip_plugin_ansi "$prefixed_unicode_render")
if printf '%s\n' "$prefixed_unicode_plain" | awk -v token="$prefixed_unicode_token" \
  '$0 == token { found=1 } END { exit !found }'; then
  pass 'Unicode tokens fitting the width move past ASCII prefixes intact'
else
  fail 'Unicode token after an ASCII prefix was split or overflowed'
fi

printf '%s\n' '{"key":"ABC-123","summary":"Summary\nSTATUS    forged\tmetadata","status":{"name":"In Progress\nLINK      forged"},"assignee":{"displayName":"Ada\nDESCRIPTION"},"updated":"today\tCOMMENTS\r\nforged","url":"https://jira.example.test/browse/ABC-123\nLINK      forged","description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"description first\tpart\nsecond line"}]}]},"comments":[{"author":{"displayName":"Reviewer\nDESCRIPTION"},"created":"today\tCOMMENTS","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"comment first\tpart\nsecond line"}]}]}}]}' \
  > "$STATE/cache/ABC-123.json"
if ! hostile_render=$(run env COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'hostile metadata render'
fi
hostile_plain=$(strip_plugin_ansi "$hostile_render")
if printf '%s\n' "$hostile_plain" | awk '
  $0 ~ /^STATUS    forged/ || $0 ~ /^LINK      forged/ { forged=1 }
   $0 ~ /^Description([ \t]|$)/ { descriptions++ }
   $0 ~ /^Comments \(1\)/ { comments++ }
  END { exit (forged || descriptions != 1 || comments != 1) }
'; then
  pass 'metadata cannot inject structural lines'
else
  fail 'metadata injected structural lines'
fi
if printf '%s\n' "$hostile_plain" | awk '
  $0 == "description first\tpart" { description=1 }
  description && $0 == "second line" { description_break=1 }
  $0 == "comment first\tpart" { comment=1 }
  comment && $0 == "second line" { comment_break=1 }
  END { exit !(description_break && comment_break) }
'; then
  pass 'body newlines and tabs remain preserved'
else
  fail 'body newlines or tabs were altered'
fi

printf '%s\n' '{"key":"ABC-123","summary":"Quiet","status":{"name":"on hold"}}' > "$STATE/cache/ABC-123.json"
if ! missing_render=$(run sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'missing description and comments render'
fi
missing_plain=$(strip_plugin_ansi "$missing_render")
case "$missing_plain" in
  *'No description or comments.'*) pass 'missing description and comments remain quiet' ;;
  *) fail 'missing description and comments headings' ;;
esac
case "$missing_plain" in
  *'(none)'*) fail 'missing description or comments became noisy' ;;
  *) pass 'missing description and comments have no placeholder noise' ;;
esac
if ! no_color_render=$(run env NO_COLOR=1 COLUMNS=80 \
  sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'NO_COLOR render'
fi
esc=$(printf '\033')
case "$no_color_render" in
  *"$esc"*) fail 'NO_COLOR removes render ANSI' ;;
  *) pass 'NO_COLOR removes render ANSI' ;;
esac

: > "$LESS_INPUT_LOG"
: > "$LESS_ENV_LOG"
if ! run env NO_COLOR=1 sh "$ROOT/scripts/viewer-reader.sh" "$ROOT/scripts" ABC-123 >/dev/null; then
  fail 'reader invocation'
fi
grep -Fqx 'q back · ↑↓ scroll · Space/b page' "$LESS_ARGS_LOG" \
  && pass 'reader uses concise less help' || fail 'reader uses concise less help'
expected_less_so=$(printf 'so=\033[2m')
expected_less_se=$(printf 'se=\033[0m')
grep -Fqx "$expected_less_so" "$LESS_ENV_LOG" && grep -Fqx "$expected_less_se" "$LESS_ENV_LOG" \
  && pass 'reader passes muted less standout overrides' \
  || fail 'reader passes muted less standout overrides'
awk 'NR == 1 && $0 == "Issue details" { found=1 } END { exit !found }' "$LESS_INPUT_LOG" \
  && pass 'reader adds details heading' || fail 'reader adds details heading'

printf '%s\n' ABC-123 > "$STATE/candidates"
export FZF_DEFAULT_OPTS='--no-such-option'; export FZF_DEFAULT_COMMAND='bad'; export FZF_DEFAULT_OPTS_FILE='bad'
: > "$FZF_ENV_LOG"
if ! run env COLUMNS=180 sh "$ROOT/scripts/viewer.sh" >/dev/null; then
  fail 'wide viewer launch'
fi
if awk 'NR==1&&$0=="--help:::"{a=1} NR==2&&$0=="--ansi:::"{b=1} END{exit !(a&&b&&NR==2)}' "$FZF_ENV_LOG"; then
  pass 'polluted fzf defaults are cleared for help and picker'
else
  fail 'polluted fzf defaults are cleared for help and picker'
fi
unset FZF_DEFAULT_OPTS FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS_FILE
wide_preview=$(awk '$0 == "--preview-window" { getline; print; exit }' "$FZF_ARGS_LOG")
[ "$wide_preview" = 'right,62%,wrap,border-left,nohidden' ] \
  && pass 'wide terminals use a right preview' \
  || fail 'wide terminals use a right preview'
if awk '$0 == "--border=none" { found=1 } END { exit !found }' "$FZF_ARGS_LOG"; then
  pass 'viewer leaves the outer pane frame to Herdr'
else
  fail 'viewer leaves the outer pane frame to Herdr'
fi
wide_header=$(awk '$0 == "--header" { getline; print; exit }' "$FZF_ARGS_LOG")
[ -z "$wide_header" ] && pass 'modern picker keeps compact header' || fail 'modern picker keeps compact header'
printf '%s\n' "$FZF_ARGS_LOG" >/dev/null
mkdir -p "$TMP/help-state"
modern_help=$(env VIEWER_STATE_DIR="$TMP/help-state" sh "$ROOT/scripts/viewer-rows.sh" help)
for control in Up/Down Enter 'q back' Esc PgUp/PgDn Ctrl-D/U Ctrl-R Ctrl-G Ctrl-O Ctrl-Y Ctrl-L; do
  printf '%s\n' "$modern_help" | grep -Fq "$control" || fail "expanded picker help includes $control"
done
pass 'expanded picker help covers every control'
case "$modern_help" in
  *'choose · Type filters'*'issue (q back) · Esc close'*'browser · Ctrl-Y copy key · Ctrl-L copy link'*) pass 'picker help uses grouped middle dots' ;;
  *) fail 'picker help uses grouped middle dots' ;;
esac
rm -f "$TMP/help-state/ui-help"
header_default=$(env VIEWER_STATE_DIR="$TMP/help-state" VIEWER_HAS_FOOTER=0 sh "$ROOT/scripts/viewer-rows.sh" header)
case "$header_default" in *'Enter Read · Ctrl-O Open · F1 Help · Esc Close'*) pass 'compact header uses grouped middle dots' ;; *) fail 'compact header uses grouped middle dots' ;; esac
printf '%s\n' 'Refreshing' > "$TMP/help-state/ui-message"
header_message=$(env VIEWER_STATE_DIR="$TMP/help-state" VIEWER_HAS_FOOTER=0 sh "$ROOT/scripts/viewer-rows.sh" header)
case "$header_message" in *'Refreshing · F1 Help · Esc Close'*) pass 'ui-message header uses grouped middle dots' ;; *) fail 'ui-message header uses grouped middle dots' ;; esac
for footer_width in 30 50 80; do
  footer=$(env VIEWER_STATE_DIR="$TMP/help-state" FZF_COLUMNS="$footer_width" sh "$ROOT/scripts/viewer-rows.sh" footer)
  case "$footer_width:$footer" in
    30:*'F1 Help · Esc Close') : ;;
    50:*'Enter Read · Ctrl-O Open · F1 Help · Esc Close') : ;;
     80:*'Enter Read · Ctrl-O Open · PgUp/PgDn Scroll · F1 Help · Esc Close') : ;;
    *) fail "footer middle-dot layout at width $footer_width" ;;
  esac
done
pass 'responsive footer uses grouped middle dots'
footer_45=$(env VIEWER_STATE_DIR="$TMP/help-state" FZF_COLUMNS=45 sh "$ROOT/scripts/viewer-rows.sh" footer)
if printf '%s\n' "$footer_45" | awk 'NR == 2 && $0 == "F1 Help · Esc Close" { found=1 } END { exit !found }'; then
  pass 'footer keeps compact layout at width 45'
else
  fail 'footer keeps compact layout at width 45'
fi
footer_46=$(env VIEWER_STATE_DIR="$TMP/help-state" FZF_COLUMNS=46 sh "$ROOT/scripts/viewer-rows.sh" footer)
case "$footer_46" in *'Enter Read · Ctrl-O Open · F1 Help · Esc Close') pass 'footer uses medium layout at width 46' ;; *) fail 'footer uses medium layout at width 46' ;; esac
awk '$0 == "--footer" { footer=1 } $0 == "--info-command" { info=1 } $0 == "--highlight-line" { highlight=1 } END { exit !(footer && info && highlight) }' "$FZF_ARGS_LOG" \
  && pass 'modern fzf options are enabled' || fail 'modern fzf options are enabled'
prompt_arg=$(awk '$0 == "--prompt" { getline; print; exit }' "$FZF_ARGS_LOG")
[ "$prompt_arg" = 'Filter > ' ] && pass 'picker prompt uses literal Filter >' || fail 'picker prompt uses literal Filter >'
wide_footer=$(awk '$0 == "--footer" { getline; print; exit }' "$FZF_ARGS_LOG")
case "$wide_footer" in *ABC-123*|*Done*|*Portable*) fail 'modern footer omits issue row data' ;; *) pass 'modern footer is a single non-row argument' ;; esac
run env FZF_OLD_MODE=1 COLUMNS=180 sh "$ROOT/scripts/viewer.sh" >/dev/null || fail 'legacy fzf mode launch'
if awk '$0 == "--footer" || $0 == "--info-command" || $0 == "--highlight-line" { found=1 } END { exit found }' "$FZF_ARGS_LOG"; then
  pass 'legacy fzf mode omits modern-only options'
else
  fail 'legacy fzf mode omits modern-only options'
fi
wide_row=$(strip_picker_ansi "$(sed -n '1p' "$FZF_INPUT_LOG")")
if printf '%s\n' "$wide_row" | awk -F '\t' \
  'NF == 2 && $1 == "ABC-123" && $2 ~ /^ABC-123[[:space:]]+on hold[[:space:]]+Quiet$/'; then
  pass 'picker rows keep compact searchable status text'
else
  fail 'picker rows keep compact searchable status text'
fi
if ! run env COLUMNS=99 LINES=40 sh "$ROOT/scripts/viewer.sh" >/dev/null; then
  fail 'narrow viewer launch'
fi
narrow_preview=$(awk '$0 == "--preview-window" { getline; print; exit }' "$FZF_ARGS_LOG")
[ "$narrow_preview" = 'down,36,wrap,border-top,nohidden' ] \
  && pass 'narrow terminals use a down preview' \
  || fail 'narrow terminals use a down preview'
if ! run env NO_COLOR=1 COLUMNS=120 sh "$ROOT/scripts/viewer.sh" >/dev/null; then
  fail 'NO_COLOR viewer launch'
fi
no_color_row=$(sed -n '1p' "$FZF_INPUT_LOG")
esc=$(printf '\033')
case "$no_color_row" in
  *"$esc"*) fail 'NO_COLOR removes picker ANSI' ;;
  *) pass 'NO_COLOR removes picker ANSI' ;;
esac

# Renderer semantic coverage: structured inline content must render as text,
# while arbitrary attributes and malformed siblings remain invisible.
printf '%s\n' '{"key":"ABC-123","summary":"Semantic","status":{"name":"Done"},"updated":"2026-09-03T12:34:56.123456Z","url":"https://jira.example.test/browse/ABC-123","description":{"type":"doc","content":[{"type":"mediaSingle","content":[{"type":"media","attrs":{"alt":"photo.png","evil":{"leak":"no"}}}]},{"type":"mediaGroup","content":[{"type":"media","attrs":{"filename":"report.pdf"}}]},{"type":"blockCard","attrs":{"url":"https://block.example"}},{"type":"orderedList","content":[null,{"content":[{"type":"paragraph","content":[{"type":"text","text":"ordered survives"}]}]}]},{"type":"paragraph","attrs":{"secret":"hidden"},"content":[{"type":"emoji","attrs":{"shortName":":sparkles:"}},{"type":"mention","attrs":{"text":"Ada"}},{"type":"text","text":"literal {\"json\":true}","marks":[{"type":"link","attrs":{"href":"https://example.test"}}]},{"type":"inlineCard","attrs":{"url":"https://card.example"}},{"type":"unknown","attrs":{"secret":"hidden"},"content":[{"type":"text","text":"nested survives"}]}]},{"type":"codeBlock","content":[{"type":"text","text":"{\"code\":true}"}]}]}}' > "$STATE/cache/ABC-123.json"
semantic_preview=$(run env NO_COLOR=1 FZF_PREVIEW_COLUMNS=200 sh "$ROOT/scripts/render.sh" ABC-123)
case "$semantic_preview" in *'UPDATED   '*|*'LINK      '*) fail 'preview omits full-reader metadata' ;; esac
case "$semantic_preview" in *'ABC-123 · Done'*'unassigned · Updated 3 Sep 2026, 12:34 UTC'*) pass 'preview header metadata uses middle dots' ;; *) fail 'preview header metadata uses middle dots' ;; esac
case "$semantic_preview" in
  *'[Image: photo.png]'*'[Attachment: report.pdf]'*'block.example'*'2. ordered survives'*':sparkles:'*Ada*'literal {"json":true} (https://example.test)'*'https://card.example'*'nested survives'*'{"code":true}'*) pass 'semantic ADF content renders safely' ;; *) fail 'semantic ADF content renders safely' ;; esac
case "$semantic_preview" in *'evil'*|*'secret'*|*'"leak"'*) fail 'ADF attributes do not leak' ;; esac
semantic_full=$(run env NO_COLOR=1 COLUMNS=200 sh "$ROOT/scripts/render.sh" ABC-123)
case "$semantic_full" in *'ABC-123 · Done'*'unassigned · Updated 3 Sep 2026, 12:34 UTC'*'UPDATED   2026-09-03T12:34:56.123456Z'*'LINK      https://jira.example.test/browse/ABC-123'*) pass 'full renderer preserves dotted header and exact updated metadata and URL' ;; *) fail 'full renderer preserves dotted header and exact updated metadata and URL' ;; esac
for zone in +0700 +07:00; do
  printf '%s\n' "{\"key\":\"ABC-123\",\"summary\":\"Zone\",\"updated\":\"2026-09-03T12:34:56$zone\"}" > "$STATE/cache/ABC-123.json"
  zone_render=$(run env COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123)
  case "$zone_render" in *'Updated 3 Sep 2026, 12:34 +07:00'*) : ;; *) fail "timezone $zone normalized" ;; esac
done
pass 'timezone offsets normalize consistently'
printf '%s\n' '{"key":"ABC-123","summary":"Wrapped title has enough words to continue","status":{"name":"Done"}}' > "$STATE/cache/ABC-123.json"
wrapped_title=$(run env FZF_PREVIEW_COLUMNS=18 COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123)
bold=$(printf '\033[1m')
case "$wrapped_title" in *"$bold"'Wrapped title'*'enough words'*) pass 'wrapped title retains ANSI styling and continuation' ;; *) fail 'wrapped title ANSI styling or continuation' ;; esac
printf '%s\n' '{"key":"ABC-123","summary":"Malformed","updated":"2026-09-03T12:34:56Z","description":{"type":"doc","content":[null,{},[],{"type":"paragraph","content":[{"type":"text","text":"keep\r\u001b[31m text"}]}]},"comments":[null,{"body":[]}]}' > "$STATE/cache/ABC-123.json"
if ! malformed=$(run env NO_COLOR=1 COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123); then fail 'malformed ADF renders safely'; fi
esc=$(printf '\033')
case "$malformed" in *"$esc"*) fail 'malformed ADF preserves no terminal controls' ;; *) pass 'malformed ADF renders safely without controls' ;; esac
if awk '$0 == "--no-color" { found=1 } END { exit !found }' "$FZF_ARGS_LOG"; then
  pass 'NO_COLOR passes the fzf option'
else
  fail 'NO_COLOR passes the fzf option'
fi
if ! fallback_output=$(printf 'q\n' | run env FZF_EXIT_STATUS=2 COLUMNS=80 \
  sh "$ROOT/scripts/viewer.sh"); then
  fail 'fzf parser failure fallback'
fi
fallback_plain=$(strip_plugin_ansi "$fallback_output")
case "$fallback_plain" in
  *'Jira Peek: 1 issue(s)'*'1) ABC-123'*'Number/exact key or Enter reads.'*'q closes.'*)
     pass 'fzf startup failure shows the issue menu' ;;
  *) fail 'fzf parser failure fallback output' ;;
esac
pass 'startup failure menu instructions'

export TWG_MODE=nonzero
export FZF_STDERR='password="alpha beta gamma"'
if ! fallback_diagnostic=$(printf 'q\n' | run env FZF_EXIT_STATUS=2 COLUMNS=80 \
  sh "$ROOT/scripts/viewer.sh" 2>&1); then
  fail 'fzf fallback pager diagnostic'
fi
case "$fallback_diagnostic" in *alpha*|*beta*|*gamma*|*password*) fail 'startup diagnostic leaked credential content' ;; *'picker unavailable:'*) pass 'startup diagnostic is safe' ;; *) fail 'startup diagnostic is safe' ;; esac
export TWG_MODE=
unset FZF_STDERR

export FZF_STDERR='failed to listen on fzf.sock'
if ! safe_fallback_message=$(printf 'q\n' | run env FZF_EXIT_STATUS=2 COLUMNS=80 \
  sh "$ROOT/scripts/viewer.sh" 2>&1); then
  fail 'fzf safe diagnostic fallback'
fi
case "$safe_fallback_message" in
  *'failed to listen on fzf.sock'*) pass 'fzf safe diagnostic reaches fallback menu' ;;
  *) fail 'fzf safe diagnostic reaches fallback menu' ;;
esac
unset FZF_STDERR

NO_FZF_BIN="$TMP/no-fzf-bin"
mkdir "$NO_FZF_BIN"
for tool in env sh sed awk tr wc mktemp mkdir rmdir mv rm cp ps sleep jq less twg herdr cat grep find date dirname tee chmod cksum uname basename sort head cut readlink tput cmp; do
  tool_path=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$tool_path" ] && ln -s "$tool_path" "$NO_FZF_BIN/$tool"
done
NO_LESS_BIN="$TMP/no-less-bin"
mkdir "$NO_LESS_BIN"
for tool in env sh sed awk tr wc mktemp mkdir mv rm cp ps sleep jq twg cat grep find date dirname tee chmod cksum uname basename sort head cut readlink tput cmp; do
  tool_path=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$tool_path" ] && ln -s "$tool_path" "$NO_LESS_BIN/$tool"
done
if doctor_no_less=$(env PATH="$NO_LESS_BIN" PAGER=cat HERDR_PLUGIN_CONFIG_DIR="$DOCTOR_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$DOCTOR_STATE" sh "$ROOT/scripts/doctor.sh" 2>&1); then
  fail 'doctor accepts configured PAGER without less'
fi
case "$doctor_no_less" in
  *'FAIL no pager found; install less'*) pass 'doctor requires less despite configured PAGER' ;;
  *) fail 'doctor less-only diagnostic' ;;
esac

missing_fzf_twg_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
: >> "$HERDR_LOG"
missing_fzf_herdr_before=$(wc -l < "$HERDR_LOG" | tr -d ' ')
for entrypoint in peek peek-url viewer; do
  if missing_fzf_output=$(env PATH="$NO_FZF_BIN" HERDR_PANE_ID=focused-pane \
    HERDR_PLUGIN_CLICKED_URL=https://jira.example.test/browse/ABC-123 \
    HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$TMP/missing-fzf-$entrypoint" \
    sh "$ROOT/scripts/$entrypoint.sh" 2>&1); then
    fail "$entrypoint accepts missing fzf"
  fi
  case "$missing_fzf_output" in
    *'fzf is required'*'brew install fzf'*'PATH used by Herdr'*) pass "$entrypoint explains how to install fzf" ;;
    *) fail "$entrypoint missing-fzf diagnostic" ;;
  esac
done
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$missing_fzf_twg_before" ] || fail 'missing fzf invokes TWG'
[ "$(wc -l < "$HERDR_LOG" | tr -d ' ')" = "$missing_fzf_herdr_before" ] || fail 'missing fzf reads or opens a pane'
if missing_fzf_doctor=$(env PATH="$NO_FZF_BIN" HERDR_PLUGIN_CONFIG_DIR="$DOCTOR_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$DOCTOR_STATE" sh "$ROOT/scripts/doctor.sh" 2>&1); then
  fail 'doctor accepts missing fzf'
fi
case "$missing_fzf_doctor" in
  *'FAIL fzf is required'*'brew install fzf'*) pass 'doctor requires fzf with installation instructions' ;;
  *) fail 'doctor missing-fzf diagnostic' ;;
esac

VIEWER_MANY_CONFIG="$TMP/viewer-many-config"
VIEWER_MANY_STATE="$TMP/viewer-many-state"
VIEWER_MANY_BIN="$TMP/viewer-many-bin"
mkdir -p "$VIEWER_MANY_CONFIG" "$VIEWER_MANY_STATE/cache" "$VIEWER_MANY_BIN"
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="ABC"' 'CACHE_TTL_MIN=10' 'MAX_CANDIDATES=20' > "$VIEWER_MANY_CONFIG/config.sh"
: > "$VIEWER_MANY_STATE/candidates"
i=1
while [ "$i" -le 11 ]; do
  key="ABC-$i"
  printf '%s\n' "$key" >> "$VIEWER_MANY_STATE/candidates"
  printf '%s\n' "{\"key\":\"$key\",\"summary\":\"Synthetic $i\",\"status\":{\"name\":\"Done\"},\"description\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Body $i\"}]}]}}" > "$VIEWER_MANY_STATE/cache/$key.json"
  i=$((i + 1))
done
for tool in env sh sed awk tr wc mktemp mkdir rmdir mv rm cp ps sleep jq less twg herdr cat grep find date dirname tee chmod cksum uname basename sort head cut readlink tput cmp; do
  [ "$tool" = twg ] && continue
  ln -s "$NO_FZF_BIN/$tool" "$VIEWER_MANY_BIN/$tool"
done
ln -s "$BIN/twg" "$VIEWER_MANY_BIN/twg"
ln -s "$BIN/fzf" "$VIEWER_MANY_BIN/fzf"
many_run() { env NO_COLOR=1 FZF_EXIT_STATUS=2 PATH="$VIEWER_MANY_BIN" HERDR_PLUGIN_CONFIG_DIR="$VIEWER_MANY_CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_MANY_STATE" "$@"; }
# Basic-mode rescan is source-only and must not invoke metadata.
basic_run() {
  many_run env HERDR_VIEWER_SOURCE_PANE=focused-pane HERDR_VIEWER_SOURCE_TERMINAL=terminal-source \
    HERDR_VISIBLE_TEXT='ABC-1 ABC-3' HERDR_RECENT_TEXT= HERDR_DETECTION_TEXT= \
    HERDR_VIEWER_CANDIDATES="$(printf '%s\n' ABC-1 ABC-2)" sh "$ROOT/scripts/viewer.sh"
}
# Account for metadata loaded before fzf fails and the recovery menu starts.
basic_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
printf 'q\n' | basic_run >/dev/null 2>&1 || fail 'basic startup baseline'
basic_startup_calls=$(( $(wc -l < "$TWG_LOG" | tr -d ' ') - basic_before ))
basic_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
if ! basic_output=$(printf 's\nq\n' | basic_run 2>&1); then fail 'basic s rescan'; fi
case "$basic_output" in *'Rescanning source pane...'*'Rescanned: 2 issues'*'Selected ABC-1 (2/2)'*) pass 'basic s rescan reports progress and retained selection' ;; *) fail 'basic s rescan output' ;; esac
[ "$(( $(wc -l < "$TWG_LOG" | tr -d ' ') - basic_before ))" = "$basic_startup_calls" ] || fail 'basic rescan starts no metadata calls'
[ "$(wc -l < "$VIEWER_MANY_STATE/candidates" | tr -d ' ')" = 11 ] || fail 'basic rescan keeps session candidates isolated'
pass 'basic s rescan avoids metadata calls'
many_fzf_output=$(env NO_COLOR=1 FZF_EXIT_STATUS=2 PATH="$BIN:$VIEWER_MANY_BIN" HERDR_PLUGIN_CONFIG_DIR="$VIEWER_MANY_CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_MANY_STATE" sh "$ROOT/scripts/viewer.sh" <<EOF
11
q
EOF
) || fail 'normal fzf startup failure menu selection'
case "$many_fzf_output" in *'Body 11'*) pass 'normal fzf startup failure reaches last issue' ;; *) fail 'normal fzf startup failure reaches last issue' ;; esac
[ "$(sed -n '1p' "$VIEWER_MANY_STATE/key")" = ABC-11 ] || fail 'normal fzf startup failure saves selection'
many_output=$(printf '11\nq\n' | many_run sh "$ROOT/scripts/viewer.sh") || fail '11-key menu selection'
case "$many_output" in *'ABC-11'*'Done'*'Synthetic 11'*'Body 11'*) pass 'fallback reaches last of 11 issues' ;; *) fail 'fallback reaches last of 11 issues' ;; esac
[ "$(sed -n '1p' "$VIEWER_MANY_STATE/key")" = ABC-11 ] || fail 'last issue selection is saved'
many_output=$(printf 'ABC-5\nq\n' | many_run sh "$ROOT/scripts/viewer.sh") || fail 'exact-key menu selection'
case "$many_output" in *'Body 5'*) pass 'fallback accepts exact detected key' ;; *) fail 'fallback accepts exact detected key' ;; esac
[ "$(sed -n '1p' "$VIEWER_MANY_STATE/key")" = ABC-5 ] || fail 'exact-key selection is saved'
many_output=$(printf 'n\nn\np\n\nq\n' | many_run sh "$ROOT/scripts/viewer.sh") || fail 'menu navigation'
case "$many_output" in *'Body 2'*) pass 'menu n/p navigation and Enter' ;; *) fail 'menu n/p navigation and Enter' ;; esac
many_output=$(printf '0\nABC-999\n../escape\nq\n' | many_run sh "$ROOT/scripts/viewer.sh") || fail 'invalid menu input termination'
case "$many_output" in *'Unknown issue.'*'q closes.'*) pass 'invalid menu choices are rejected' ;; *) fail 'invalid menu choices are rejected' ;; esac
many_output=$(many_run sh "$ROOT/scripts/viewer.sh" </dev/null) || fail 'menu EOF termination'
pass 'menu EOF terminates'

if [ -n "$REAL_FZF_PATH" ] && [ -n "$REAL_LESS_PATH" ] && [ -x "$(command -v expect 2>/dev/null || true)" ]; then
  expect "$ROOT/tests/viewer-pty.exp" "$ROOT" "$TMP" "$REAL_FZF_PATH" "$REAL_LESS_PATH" || fail 'viewer PTY regression'
else
  pass 'viewer PTY regression skipped (fzf or expect unavailable)'
fi

if [ -n "$REAL_FZF_PATH" ]; then
  REAL_WRAP="$TMP/real-fzf-wrapper"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" > "$REAL_FZF_ARGS_LOG"' '"$REAL_FZF_PATH_VALUE" --help >/dev/null 2>&1; help_status=$?; printf "%s\n" "$help_status" > "$REAL_FZF_HELP_STATUS"' '"$REAL_FZF_PATH_VALUE" --filter=ABC-123 "$@"; status=$?; printf "%s\n" "$status" > "$REAL_FZF_STATUS"; exit "$status"' > "$REAL_WRAP"
  chmod 700 "$REAL_WRAP"
  ln -sf "$REAL_WRAP" "$TMP/fzf"
  real_fzf_output_file="$TMP/real-fzf-output"
  real_fzf_status=0
  run env PATH="$TMP:$BIN:$ORIGINAL_PATH" REAL_FZF_PATH_VALUE="$REAL_FZF_PATH" REAL_FZF_ARGS_LOG="$TMP/real-fzf-args" REAL_FZF_STATUS="$TMP/real-fzf-status" REAL_FZF_HELP_STATUS="$TMP/real-fzf-help-status" FZF_DEFAULT_OPTS= FZF_DEFAULT_COMMAND= FZF_DEFAULT_OPTS_FILE= COLUMNS=120 \
    sh "$ROOT/scripts/viewer.sh" > "$real_fzf_output_file" 2>&1 \
    || real_fzf_status=$?
  case "$real_fzf_status" in
    0|1) pass 'real fzf parses viewer options (no selection is acceptable)' ;;
    2) fail 'real fzf smoke parser failure (status 2)' ;;
    *) fail 'real fzf smoke returned unexpected status' ;;
  esac
  case "$(sed -n '1p' "$TMP/real-fzf-status")" in 0|1) pass 'real fzf wrapper recorded underlying status' ;; *) fail 'real fzf wrapper status' ;; esac
  case "$(sed -n '1p' "$TMP/real-fzf-help-status")" in 0|1) pass 'real fzf help invocation succeeded' ;; *) fail 'real fzf help invocation' ;; esac
  real_fzf_output=$(sed -n '1,$p' "$real_fzf_output_file")
  case "$real_fzf_output" in *'picker unavailable'*) fail 'real fzf did not use fallback' ;; esac
  case "$real_fzf_status:$real_fzf_output" in
    2:*) fail 'real fzf smoke used the status-2 fallback' ;;
  esac
  if find "$STATE" -type f -name '.*' -print | grep -q .; then
    fail 'real fzf smoke left temporary state files'
  fi
else
  pass 'real fzf smoke skipped (not installed)'
fi

# A loading row is immediately renderable and its preview must not fetch again.
VIEWER_TEST_STATE="$TMP/viewer-progress"
mkdir -p "$VIEWER_TEST_STATE/rows"
mkdir -p "$VIEWER_TEST_STATE/cache"
printf '%s\n' '{"key":"ABC-123","summary":"Portable peek","status":{"name":"Done"}}' > "$VIEWER_TEST_STATE/cache/ABC-123.json"
printf '%s\n%s\n%s\n' ../../escape ABC-123 DEF-9 > "$VIEWER_TEST_STATE/candidates"
printf '%s\n' 'escape\tescape  Blocked  must-not-render' > "$TMP/escape"
printf '%s\n' ABC-123 DEF-9 > "$VIEWER_TEST_STATE/snapshot-input"
if ! loading_rows=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_TEST_STATE" \
  VIEWER_STATE_DIR="$VIEWER_TEST_STATE" sh "$ROOT/scripts/viewer-rows.sh"); then
  fail 'progressive rows render before fetch completion'
fi
printf '%s\n' "$loading_rows" | awk -F '\t' 'NF==2 && NR==1 && $1=="ABC-123" && $2 ~ /^ABC-123[[:space:]]+fetching\.\.\.[[:space:]]*$/ { a=1 } NF==2 && NR==2 && $1=="DEF-9" && $2 ~ /^DEF-9[[:space:]]+fetching\.\.\.[[:space:]]*$/ { b=1 } END { exit !(a && b) }' \
  || fail 'progressive loading rows preserve order'
case "$loading_rows" in
  *escape*) fail 'progressive rows accepted a traversal candidate' ;;
esac
before_fetch=$(wc -l < "$TWG_LOG" | tr -d ' ')
if ! env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_TEST_STATE" \
  VIEWER_STATE_DIR="$VIEWER_TEST_STATE" sh "$ROOT/scripts/viewer-fetch.sh" ABC-123; then
  fail 'progressive worker publishes resolved row'
fi
snapshot=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_TEST_STATE" \
  VIEWER_STATE_DIR="$VIEWER_TEST_STATE" sh "$ROOT/scripts/viewer-rows.sh")
printf '%s\n' "$snapshot" | awk -F '\t' 'NF==2 && NR==1 && $1=="ABC-123" && $2 ~ /^ABC-123[[:space:]]+Done[[:space:]]+Portable peek$/ { a=1 } NF==2 && NR==2 && $1=="DEF-9" && $2 ~ /^DEF-9[[:space:]]+fetching\.\.\.[[:space:]]*$/ { b=1 } END { exit !(a && b) }' \
  || fail 'resolved row publishes before slower row'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$before_fetch" ] || fail 'resolved row cache hit refetched'
before_preview=$(wc -l < "$TWG_LOG" | tr -d ' ')
preview=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_TEST_STATE" \
  VIEWER_STATE_DIR="$VIEWER_TEST_STATE" sh "$ROOT/scripts/viewer-preview.sh" DEF-9)
[ "$preview" = 'Fetching issue...' ] || fail 'loading preview placeholder'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$before_preview" ] || fail 'loading preview did not refetch'
pass 'progressive loading rows and fetch-free loading preview'

FAIL_VIEWER_STATE="$TMP/viewer-failure"
FAIL_VIEWER_TWG_LOG="$TMP/viewer-failure-twg.log"
: > "$FAIL_VIEWER_TWG_LOG"
mkdir -p "$FAIL_VIEWER_STATE/rows" "$FAIL_VIEWER_STATE/failed"
printf '%s\n' DEF-9 > "$FAIL_VIEWER_STATE/candidates"
if ! env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$FAIL_VIEWER_STATE" \
  VIEWER_STATE_DIR="$FAIL_VIEWER_STATE" TWG_LOG="$FAIL_VIEWER_TWG_LOG" TWG_MODE=nonzero TWG_STDERR='denied' \
  sh "$ROOT/scripts/viewer-fetch.sh" DEF-9; then fail 'failed progressive worker'; fi
fail_snapshot=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$FAIL_VIEWER_STATE" VIEWER_STATE_DIR="$FAIL_VIEWER_STATE" sh "$ROOT/scripts/viewer-rows.sh")
case "$fail_snapshot" in *'(could not load)'*) : ;; *) fail 'failed progressive row' ;; esac
fail_before_preview=$(wc -l < "$FAIL_VIEWER_TWG_LOG" | tr -d ' ')
if fail_preview=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$FAIL_VIEWER_STATE" VIEWER_STATE_DIR="$FAIL_VIEWER_STATE" TWG_LOG="$FAIL_VIEWER_TWG_LOG" sh "$ROOT/scripts/viewer-preview.sh" DEF-9 2>&1); then fail 'failed preview unexpectedly succeeded'; fi
case "$fail_preview" in *'Could not load DEF-9: Jira request failed'*) : ;; *) fail 'failed preview diagnostic' ;; esac
[ "$(wc -l < "$FAIL_VIEWER_TWG_LOG" | tr -d ' ')" = "$fail_before_preview" ] || fail 'failed preview refetched'
pass 'failed row preview reuses diagnostic'

NONOBJECT_STATE="$TMP/viewer-nonobject"
mkdir -p "$NONOBJECT_STATE/rows" "$NONOBJECT_STATE/failed" "$NONOBJECT_STATE/cache"
printf '%s\n' ABC-123 > "$NONOBJECT_STATE/candidates"
printf '%s\n' '{"key":"ABC-123","status":"Done","summary":"Portable peek"}' > "$NONOBJECT_STATE/cache/ABC-123.json"
env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$NONOBJECT_STATE" VIEWER_STATE_DIR="$NONOBJECT_STATE" sh "$ROOT/scripts/viewer-fetch.sh" ABC-123 || fail 'non-object status worker'
nonobject_rows=$(env HERDR_PLUGIN_CONFIG_DIR="$CONFIG" HERDR_PLUGIN_STATE_DIR="$NONOBJECT_STATE" VIEWER_STATE_DIR="$NONOBJECT_STATE" sh "$ROOT/scripts/viewer-rows.sh")
printf '%s\n' "$nonobject_rows" | awk -F '\t' 'NF==2 && $1=="ABC-123" && $2 ~ /^ABC-123[[:space:]]+\?[[:space:]]+Portable peek[[:space:]]*$/ { ok=1 } END { exit !ok }' || fail 'non-object status publishes row'
pass 'non-object status publishes unknown status'

PUBLISHED_STATE="$TMP/viewer-published"
PUBLISHED_LOG="$TMP/viewer-published-twg.log"
mkdir -p "$PUBLISHED_STATE/rows" "$PUBLISHED_STATE/failed"; : > "$PUBLISHED_LOG"
printf '%s\n' ABC-123 > "$PUBLISHED_STATE/candidates"
if ! env HERDR_PLUGIN_CONFIG_DIR="$ZERO_CONFIG" HERDR_PLUGIN_STATE_DIR="$PUBLISHED_STATE" \
  VIEWER_STATE_DIR="$PUBLISHED_STATE" TWG_LOG="$PUBLISHED_LOG" sh "$ROOT/scripts/viewer-fetch.sh" ABC-123; then
  fail 'published TTL-zero worker'
fi
published_before=$(wc -l < "$PUBLISHED_LOG" | tr -d ' ')
env HERDR_PLUGIN_CONFIG_DIR="$ZERO_CONFIG" HERDR_PLUGIN_STATE_DIR="$PUBLISHED_STATE" \
  VIEWER_STATE_DIR="$PUBLISHED_STATE" TWG_LOG="$PUBLISHED_LOG" sh "$ROOT/scripts/viewer-preview.sh" ABC-123 >/dev/null \
  || fail 'published TTL-zero preview'
[ "$(wc -l < "$PUBLISHED_LOG" | tr -d ' ')" = "$((published_before + 1))" ] \
  || fail 'published preview refetched at TTL zero'
[ ! -e "$PUBLISHED_STATE/cache/ABC-123.json" ] \
  || fail 'published TTL-zero worker created durable issue cache'
if find "$PUBLISHED_STATE" -type f -name '.issue-*' -print | grep -q .; then
  fail 'published TTL-zero worker left a temporary issue payload'
fi
pass 'published preview refetches without durable TTL-zero issue data'

printf '%s\n' \
  '{"key":"ABC-123","url":"https://jira.example.test/browse/ABC-123?source=test#fragment"}' \
  > "$STATE/cache/ABC-123.json"
cached_url=$(run sh -c '. "$1/scripts/common.sh"; issue_url ABC-123' sh "$ROOT")
[ "$cached_url" = 'https://jira.example.test/browse/ABC-123?source=test#fragment' ] \
  || fail 'cached query-then-fragment URL accepted'
printf '%s\n' \
  '{"key":"ABC-123","url":"https://jira.example.test/browse/ABC-123#fragment?value"}' \
  > "$STATE/cache/ABC-123.json"
cached_url=$(run sh -c '. "$1/scripts/common.sh"; issue_url ABC-123' sh "$ROOT")
[ "$cached_url" = 'https://jira.example.test/browse/ABC-123#fragment?value' ] \
  || fail 'cached fragment-containing-query URL accepted'
pass 'cached issue_url handles query and fragment order'

printf '%s\n' '{"key":"ABC-123","summary":"Portable\u001b[31m\tpeek\nnext\u009b31m","status":{"name":"Done\u001b[31m"},"assignee":{"displayName":"Ada\u001b]8;;https://evil\u0007Lovelace"},"updated":"2026\u009b31m-09-03","url":"https://jira.example.test/browse/ABC-123?from=twg","description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Description\u001b[2J\ttext\nnext\u009d"}]}]},"comments":[{"author":{"displayName":"Reviewer\u001b[31m"},"created":"2026\u001b[2J","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Looks\tgood\nnext\u009c"}]}]}}]}' \
  > "$STATE/cache/ABC-123.json"
if ! sanitized=$(run env COLUMNS=80 sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'remote text sanitization'
fi
bold=$(printf '\033[1m')
case "$sanitized" in
  *"$bold"*) pass 'plugin ANSI remains available' ;;
  *) fail 'plugin ANSI was removed' ;;
esac
plain=$(strip_plugin_ansi "$sanitized")
control_free=$(printf '%s' "$plain" | LC_ALL=C tr -d '\001-\010\013\014\016-\037\177-\237')
[ "$plain" = "$control_free" ] || fail 'remote terminal controls remain'
tab=$(printf '\t')
case "$plain" in
  *"$tab"*) pass 'remote tab layout preserved' ;;
  *) fail 'remote tab layout lost' ;;
esac
if printf '%s' "$plain" | awk 'last ~ /text$/ && $0 == "next" { found=1 } { last=$0 } END { exit !found }'; then
  pass 'remote newline layout preserved'
else
  fail 'remote newline layout lost'
fi
case "$plain" in
  *'Description[2J'*'Looks'*'good'*) pass 'remote render text sanitized' ;;
  *) fail 'remote render text was lost' ;;
esac
if ! row=$(run sh "$ROOT/scripts/fetch.sh" ABC-123); then
  fail 'remote picker text sanitization'
fi
if ! printf '%s\n' "$row" | awk -F '\t' \
  'NR == 1 && NF == 3 && $1 == "ABC-123" && $2 ~ /Done/ && $3 ~ /Portable/ && $3 ~ /peek/ && $3 ~ /next/ { ok=1 } END { exit !(ok && NR == 1) }'; then
  fail 'remote picker row shape or useful text'
fi
row_without_tabs=$(printf '%s' "$row" | tr -d '\t')
row_control_free=$(printf '%s' "$row_without_tabs" | LC_ALL=C tr -d '\000-\037\177-\237')
[ "$row_without_tabs" = "$row_control_free" ] || fail 'remote picker controls remain'
pass 'remote picker text sanitized'

printf '%s\n' '{"key":"DEF-9"}' > "$STATE/cache/ABC-123.json"
wrong_key_before=$(wc -l < "$TWG_LOG" | tr -d ' ')
run sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'wrong-key cache refresh'
[ "$(wc -l < "$TWG_LOG" | tr -d ' ')" = "$((wrong_key_before + 1))" ] || fail 'wrong-key cache was reused'
jq -e '.key == "ABC-123" and (has("data") | not)' "$STATE/cache/ABC-123.json" >/dev/null \
  || fail 'wrong-key cache replaced'
pass 'wrong-key cache rejected'

if run sh "$ROOT/scripts/fetch.sh" '../ABC-123' >/dev/null 2>&1; then
  fail 'malicious key rejected'
fi
[ ! -f "$STATE/ABC-123.json" ] || fail 'path traversal did not create cache path'
pass 'malicious key rejected'

export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"link-source-pane","focused_client_id":"client-1"}'
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/ABC-123?source=test#fragment'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ "$(sed -n '1p' "$STATE/sources/source-terminal-source/candidates")" = ABC-123 ] || fail 'configured clicked URL accepted'
pass 'query-then-fragment clicked URL accepted'
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/ABC-123#fragment?value'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ "$(sed -n '1p' "$STATE/sources/source-terminal-source/candidates")" = ABC-123 ] || fail 'fragment-containing-query clicked URL accepted'
pass 'fragment-containing-query clicked URL accepted'

export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test.evil/browse/ABC-123'
if run sh "$ROOT/scripts/peek-url.sh" >/dev/null 2>&1; then
  fail 'unrelated clicked host rejected'
fi
pass 'unrelated clicked host rejected'

SOCKET_A="$TMP/herdr-a.sock"
SOCKET_B="$TMP/herdr-b.sock"
export HERDR_SOCKET_PATH="$SOCKET_A"
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/ABC-123'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
export HERDR_SOCKET_PATH="$SOCKET_B"
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/DEF-9'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
session_a=$(session_dir "$SOCKET_A")
session_b=$(session_dir "$SOCKET_B")
[ "$session_a" != "$session_b" ] || fail 'socket sessions have distinct state paths'
[ "$(sed -n '1p' "$session_a/sources/source-terminal-source/key")" = ABC-123 ] || fail 'socket A key state'
[ "$(sed -n '1p' "$session_a/sources/source-terminal-source/candidates")" = ABC-123 ] || fail 'socket A candidate state'
[ "$(sed -n '1p' "$session_b/sources/source-terminal-source/key")" = DEF-9 ] || fail 'socket B key state'
[ "$(sed -n '1p' "$session_b/sources/source-terminal-source/candidates")" = DEF-9 ] || fail 'socket B candidate state'
pass 'socket-scoped key and candidate state'
[ -s "$session_a/sources/source-terminal-source/viewer-pane" ] || fail 'socket A viewer pane tracking'
[ -s "$session_b/sources/source-terminal-source/viewer-pane" ] || fail 'socket B viewer pane tracking'
pane_a=$(sed -n '1p' "$session_a/sources/source-terminal-source/viewer-pane")
pane_b=$(sed -n '1p' "$session_b/sources/source-terminal-source/viewer-pane")
terminal_a=$(sed -n '2p' "$session_a/sources/source-terminal-source/viewer-pane")
terminal_b=$(sed -n '2p' "$session_b/sources/source-terminal-source/viewer-pane")
[ "$pane_a" != "$pane_b" ] || fail 'socket sessions have distinct viewer panes'
[ "$terminal_a" != "$terminal_b" ] || fail 'socket sessions have distinct viewer terminals'
[ "$pane_a" != "$terminal_a" ] || fail 'viewer pane tracking stores pane ID separately'
[ "$pane_b" != "$terminal_b" ] || fail 'viewer pane tracking stores pane ID separately'
[ ! -f "$STATE/sources/source-terminal-source/viewer-pane" ] || fail 'viewer pane state is session scoped'
pass 'socket-scoped viewer pane state'
case "$(sed -n '$p' "$HERDR_LOG")" in
  *'plugin pane open --plugin jira-peek --entrypoint viewer --placement split --target-pane link-source-pane'*'--direction right'*'--focus'*)
    pass 'link-click opens an explicit right-side split' ;;
  *) fail 'link-click opens an explicit right-side split' ;;
esac

close_failure_open_count=$(sed -n '1p' "$HERDR_OPEN_COUNT")
export HERDR_SOCKET_PATH="$SOCKET_A"
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/DEF-9'
export HERDR_CLOSE_FAIL_PANE="$pane_a"
if run sh "$ROOT/scripts/peek-url.sh" >/dev/null 2>&1; then
  fail 'failed viewer close reports an error'
fi
[ "$(sed -n '1p' "$HERDR_OPEN_COUNT")" = "$close_failure_open_count" ] \
  || fail 'failed viewer close did not open a duplicate'
[ "$(sed -n '1p' "$session_a/sources/source-terminal-source/viewer-pane")" = "$pane_a" ] \
  || fail 'failed viewer close preserved pane tracking'
pass 'failed live viewer close preserves tracking'
unset HERDR_CLOSE_FAIL_PANE
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ ! -f "$session_a/sources/source-terminal-source/viewer-pane" ] || fail 'successful retry clears viewer tracking'
pass 'successful viewer close clears tracking'
export HERDR_SOCKET_PATH="$SOCKET_B"

remapped_live="$TMP/remapped-live"
awk -F '\t' -v pane="$pane_b" -v terminal="$terminal_b" \
  'BEGIN { OFS="\t" } $1 == pane { print "moved-pane", terminal, "workspace-b"; next } { print }' \
  "$HERDR_LIVE_PANES" > "$remapped_live"
mv "$remapped_live" "$HERDR_LIVE_PANES"
open_count_before=$(sed -n '1p' "$HERDR_OPEN_COUNT")
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/DEF-9'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ ! -f "$session_b/sources/source-terminal-source/viewer-pane" ] || fail 'live viewer pane tracking removed on toggle'
[ "$(sed -n '1p' "$HERDR_OPEN_COUNT")" = "$open_count_before" ] \
  || fail 'live viewer toggle did not open a duplicate'
if ! awk -v pane=moved-pane '
  $0 == "workspace list" { listed_workspaces=1 }
  $0 == "pane list --workspace workspace-a" { listed_workspace_a=1 }
  $0 == "pane list --workspace workspace-b" { listed_workspace_b=1 }
  $0 == "plugin pane close " pane { closed_moved_pane=1 }
  END { exit !(listed_workspaces && listed_workspace_a && listed_workspace_b && closed_moved_pane) }
' "$HERDR_LOG"; then
  fail 'moved viewer pane was resolved and closed'
fi
pass 'moved viewer pane toggle closes without duplicate'

printf '%s\n%s\n' stale-pane stale-terminal > "$session_b/sources/source-terminal-source/viewer-pane"
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ "$(sed -n '1p' "$HERDR_OPEN_COUNT")" = "$((open_count_before + 1))" ] \
  || fail 'stale viewer pane opens a new split'
[ "$(sed -n '1p' "$session_b/sources/source-terminal-source/viewer-pane")" != stale-pane ] \
  || fail 'stale viewer pane tracking was replaced'
[ "$(sed -n '2p' "$session_b/sources/source-terminal-source/viewer-pane")" != stale-terminal ] \
  || fail 'stale viewer terminal tracking was replaced'
pass 'stale viewer pane tracking reopens safely'

STALE_SOCKET="$TMP/herdr-stale.sock"
stale_session=$(session_dir "$STALE_SOCKET")
mkdir -p "$stale_session/.lock"
printf '%s\n' 999999999 > "$stale_session/.lock/pid"
export HERDR_SOCKET_PATH="$STALE_SOCKET"
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/ABC-123'
run sh "$ROOT/scripts/peek-url.sh" >/dev/null
[ ! -d "$stale_session/.lock" ] || fail 'stale state lock was recovered and released'
pass 'stale state lock recovery'

CONCURRENT_SOCKET="$TMP/herdr-concurrent.sock"
concurrent_session=$(session_dir "$CONCURRENT_SOCKET")
rm -f "$HERDR_OPEN_STARTED" "$HERDR_OPEN_RELEASE" \
  "$TMP/concurrent-first.out" "$TMP/concurrent-first.err" \
  "$TMP/concurrent-second.out" "$TMP/concurrent-second.err" \
  "$TMP/concurrent-second-started"
open_count_before=$(sed -n '1p' "$HERDR_OPEN_COUNT")
export HERDR_SOCKET_PATH="$CONCURRENT_SOCKET"
export HERDR_OPEN_GATE=1
export HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/ABC-123'
run env HERDR_SOCKET_PATH="$CONCURRENT_SOCKET" HERDR_OPEN_GATE=1 \
  sh "$ROOT/scripts/peek-url.sh" \
  > "$TMP/concurrent-first.out" 2> "$TMP/concurrent-first.err" &
first_pid=$!
wait_attempt=0
while [ ! -f "$HERDR_OPEN_STARTED" ] && [ "$wait_attempt" -lt 10 ]; do
  sleep 1
  wait_attempt=$((wait_attempt + 1))
done
if [ ! -f "$HERDR_OPEN_STARTED" ]; then
  : > "$HERDR_OPEN_RELEASE"
  wait "$first_pid" || true
  fail 'concurrent serialization setup reached the open gate'
fi
run env HERDR_SOCKET_PATH="$CONCURRENT_SOCKET" HERDR_OPEN_GATE=1 \
  HERDR_PLUGIN_CLICKED_URL='https://jira.example.test/browse/DEF-9' \
  sh -c ': > "$1"; exec sh "$2"' sh \
  "$TMP/concurrent-second-started" "$ROOT/scripts/peek-url.sh" \
  > "$TMP/concurrent-second.out" 2> "$TMP/concurrent-second.err" &
second_pid=$!
wait_attempt=0
while [ ! -f "$TMP/concurrent-second-started" ] && [ "$wait_attempt" -lt 10 ]; do
  sleep 1
  wait_attempt=$((wait_attempt + 1))
done
if [ ! -f "$TMP/concurrent-second-started" ]; then
  : > "$HERDR_OPEN_RELEASE"
  wait "$first_pid" || true
  wait "$second_pid" || true
  fail 'concurrent serialization second invocation started'
fi
[ "$(sed -n '1p' "$concurrent_session/sources/source-terminal-source/candidates")" = ABC-123 ] \
  || {
    : > "$HERDR_OPEN_RELEASE"
    wait "$first_pid" || true
    wait "$second_pid" || true
    fail 'candidate preparation is serialized with viewer open'
  }
: > "$HERDR_OPEN_RELEASE"
first_status=0
second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
unset HERDR_OPEN_GATE
[ "$first_status" -eq 0 ] || fail 'first serialized invocation completed'
[ "$second_status" -eq 0 ] || fail 'second serialized invocation completed'
[ "$(sed -n '1p' "$HERDR_OPEN_COUNT")" = "$((open_count_before + 1))" ] \
  || fail 'serialized concurrent invocations opened one split'
[ ! -d "$concurrent_session/.lock" ] || fail 'serialized concurrent lock was released'
[ ! -f "$concurrent_session/sources/source-terminal-source/viewer-pane" ] \
  || fail 'serialized concurrent toggle removed viewer tracking'
[ "$(sed -n '1p' "$concurrent_session/sources/source-terminal-source/candidates")" = ABC-123 ] \
  || fail 'serialized concurrent candidate handoff completed'
pass 'concurrent candidate and viewer lifecycle serialization'

unset HERDR_SOCKET_PATH
export HERDR_PLUGIN_CLICKED_URL=
export HERDR_PANE_ID=focused-pane
unset HERDR_PLUGIN_CONTEXT_JSON
: > "$HERDR_LOG"
run sh "$ROOT/scripts/peek.sh" >/dev/null
[ "$(sed -n '1p' "$STATE/sources/source-terminal-source/candidates")" = DEF-9 ] || fail 'peek selects newest pane key'
[ "$(sed -n '1p' "$STATE/sources/source-terminal-source/key")" = DEF-9 ] || fail 'peek saves newest pane key'
case "$(sed -n '$p' "$HERDR_LOG")" in
  *'plugin pane open --plugin jira-peek --entrypoint viewer --placement split --target-pane focused-pane'*'--direction right'*'--focus'*)
pass 'noninteractive peek opens adjacent split' ;;
  *) fail 'noninteractive peek opens adjacent split' ;;
esac
awk '/notification show Opening Jira Peek.*--sound none/ { feedback=1 } /pane read/ { read_seen=1; if (!feedback) late=1 } END { exit !(feedback && read_seen && !late) }' "$HERDR_LOG" \
  || fail 'opening feedback precedes source scan'
pass 'opening feedback precedes source scan even when notifications are unavailable'

# Source priority, cross-source deduplication, and detection-only fallback.
SOURCE_CONFIG="$TMP/source-config"; SOURCE_STATE="$TMP/source-state"
mkdir -p "$SOURCE_CONFIG" "$SOURCE_STATE"
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="ABC|DEF|GHI"' 'MAX_CANDIDATES=3' > "$SOURCE_CONFIG/config.sh"
export HERDR_VISIBLE_TEXT='ABC-123 DEF-9 ABC-123'
export HERDR_RECENT_TEXT='GHI-7 DEF-9'
export HERDR_DETECTION_TEXT='ABC-123 GHI-7 DEF-9 ABC-123'
: > "$HERDR_SOURCE_LOG"
env HERDR_PLUGIN_CONFIG_DIR="$SOURCE_CONFIG" HERDR_PLUGIN_STATE_DIR="$SOURCE_STATE" HERDR_PANE_ID=focused-pane HERDR_SOCKET_PATH= sh "$ROOT/scripts/peek.sh" >/dev/null || fail 'source merge fixture'
awk 'NR==1&&$0~ /--source visible$/{a=1} NR==2&&$0~ /--source recent-unwrapped$/{b=1} NR==3{bad=1} END{exit !(a&&b&&!bad)}' "$HERDR_SOURCE_LOG" || fail 'detection was not used when sources had keys'
awk 'NR==1&&$0=="ABC-123"{a=1} NR==2&&$0=="DEF-9"{b=1} NR==3&&$0=="GHI-7"{c=1} END{exit !(a&&b&&c&&NR==3)}' "$SOURCE_STATE/sources/source-terminal-source/candidates" || fail 'visible precedes recent with global dedup'
pass 'visible precedes recent with global dedup'
# Toggle the first source viewer closed before reusing its state for the
# independent detection-only scan; approved toggle-first must not rescan.
env HERDR_PLUGIN_CONFIG_DIR="$SOURCE_CONFIG" HERDR_PLUGIN_STATE_DIR="$SOURCE_STATE" HERDR_PANE_ID=focused-pane HERDR_SOCKET_PATH= \
  sh "$ROOT/scripts/peek.sh" >/dev/null || fail 'source fixture viewer close'
export HERDR_VISIBLE_TEXT=; export HERDR_RECENT_TEXT=; export HERDR_DETECTION_TEXT='ABC-123 GHI-7 DEF-9 ABC-123'
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="ABC|DEF|GHI"' 'MAX_CANDIDATES=2' > "$SOURCE_CONFIG/config.sh"
 : > "$HERDR_SOURCE_LOG"
env HERDR_PLUGIN_CONFIG_DIR="$SOURCE_CONFIG" HERDR_PLUGIN_STATE_DIR="$SOURCE_STATE" HERDR_PANE_ID=focused-pane HERDR_SOCKET_PATH= sh "$ROOT/scripts/peek.sh" >/dev/null || fail 'detection fallback fixture'
awk 'NR==3&&$0~ /--source detection$/{ok=1} END{exit !ok}' "$HERDR_SOURCE_LOG" || fail 'detection fallback source call'
awk 'NR==1&&$0=="ABC-123"{a=1} NR==2&&$0=="DEF-9"{b=1} NR==3&&$0=="GHI-7"{c=1} END{exit !(a&&b&&c&&NR==3)}' "$SOURCE_STATE/sources/source-terminal-source/candidates" || fail 'detection fallback retains all keys'
unset HERDR_VISIBLE_TEXT HERDR_RECENT_TEXT HERDR_DETECTION_TEXT
pass 'detection fallback retains all keys and is only used when both sources are empty'

# Candidate order is newest-first (last occurrence wins after de-duplication)
# regardless of the configured metadata preload size.
MAX_CONFIG="$TMP/max-config"
MAX_STATE="$TMP/max-state"
mkdir -p "$MAX_CONFIG" "$MAX_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC|DEF|GHI"' \
  'MAX_CANDIDATES=2' \
  > "$MAX_CONFIG/config.sh"
export HERDR_READ_TEXT='ABC-123 DEF-9 GHI-7 ABC-123'
if ! env HERDR_PLUGIN_CONFIG_DIR="$MAX_CONFIG" HERDR_PLUGIN_STATE_DIR="$MAX_STATE" \
  HERDR_PANE_ID=focused-pane HERDR_SOCKET_PATH= \
  sh "$ROOT/scripts/peek.sh" >/dev/null; then
  fail 'complete candidate list and newest ordering'
fi
if ! awk 'NR == 1 && $0 == "ABC-123" { first=1 } NR == 2 && $0 == "GHI-7" { second=1 } NR == 3 && $0 == "DEF-9" { third=1 } END { exit !(first && second && third && NR == 3) }' "$MAX_STATE/sources/source-terminal-source/candidates"; then
  fail 'complete candidate list and newest ordering'
fi
pass 'metadata preload size does not truncate newest-first candidates'
export HERDR_READ_TEXT=

TOO_MANY_CONFIG="$TMP/too-many-config"
TOO_MANY_STATE="$TMP/too-many-state"
mkdir -p "$TOO_MANY_CONFIG" "$TOO_MANY_STATE"
printf '%s\n' \
  'JIRA_BASE="https://jira.example.test"' \
  'JIRA_SITE="jira-example"' \
  'JIRA_PROJECTS="ABC"' \
  'MAX_CANDIDATES=101' \
  > "$TOO_MANY_CONFIG/config.sh"
if too_many_output=$(env HERDR_PLUGIN_CONFIG_DIR="$TOO_MANY_CONFIG" \
  HERDR_PLUGIN_STATE_DIR="$TOO_MANY_STATE" \
  sh "$ROOT/scripts/fetch.sh" ABC-123 2>&1); then
  fail 'MAX_CANDIDATES upper bound'
fi
case "$too_many_output" in
  *'MAX_CANDIDATES must not exceed 100'*) pass 'MAX_CANDIDATES upper bound' ;;
  *) fail 'MAX_CANDIDATES upper-bound diagnostic' ;;
esac

printf '%s\n' ABC-123 > "$STATE/sources/source-terminal-source/key"
export FAKE_UNAME=Darwin
run sh "$ROOT/scripts/open-browser.sh"
[ "$(sed -n '1p' "$OPEN_LOG")" = 'https://jira.example.test/browse/ABC-123?from=twg' ] \
  || fail 'macOS browser uses TWG URL'
run sh "$ROOT/scripts/open-browser.sh" --copy-key ABC-123
[ "$(sed -n '1p' "$COPY_LOG")" = ABC-123 ] || fail 'macOS clipboard selection'
pass 'macOS browser and clipboard selection'

export FAKE_UNAME=Linux
run sh "$ROOT/scripts/open-browser.sh"
[ "$(sed -n '1p' "$OPEN_LOG")" = 'https://jira.example.test/browse/ABC-123?from=twg' ] \
  || fail 'Linux browser uses TWG URL'
run sh "$ROOT/scripts/open-browser.sh" --copy-link ABC-123
[ "$(sed -n '1p' "$COPY_LOG")" = 'https://jira.example.test/browse/ABC-123?from=twg' ] \
  || fail 'Linux clipboard uses TWG URL'
pass 'Linux browser and clipboard selection'

printf '%s\n' '{"key":"ABC-123","url":"https://foreign.example.test/browse/ABC-123"}' > "$STATE/cache/ABC-123.json"
if ! foreign_render=$(run sh "$ROOT/scripts/render.sh" ABC-123); then
  fail 'foreign cached URL render fallback'
fi
case "$foreign_render" in
  *foreign.example.test*) fail 'foreign cached URL rendered' ;;
  *'https://jira.example.test/browse/ABC-123'*) pass 'foreign cached URL render fallback' ;;
  *) fail 'configured URL missing from render fallback' ;;
esac
run sh "$ROOT/scripts/open-browser.sh"
[ "$(sed -n '1p' "$OPEN_LOG")" = 'https://jira.example.test/browse/ABC-123' ] \
  || fail 'foreign cached URL opened'
pass 'foreign cached URL browser fallback'
run sh "$ROOT/scripts/open-browser.sh" --copy-link ABC-123
[ "$(sed -n '1p' "$COPY_LOG")" = 'https://jira.example.test/browse/ABC-123' ] \
  || fail 'configured URL fallback'
pass 'configured URL fallback'

sh "$ROOT/tests/rescan.sh"
OVERFLOW_REAL_FZF="$REAL_FZF_PATH" sh "$ROOT/tests/overflow.sh"
sh "$ROOT/tests/multipane.sh"
pass 'all runtime tests passed'
printf 'all tests passed\n'
