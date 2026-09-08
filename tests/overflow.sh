#!/bin/sh
# Regression: a key beyond the metadata batch must survive every picker stage.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-overflow.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 15
mkdir -p "$tmp/bin" "$tmp/config" "$tmp/state" "$tmp/viewer/rows" "$tmp/viewer/failed"
real_fzf=${OVERFLOW_REAL_FZF-$(command -v fzf || true)}
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="TF"' 'MAX_CANDIDATES=20' > "$tmp/config/config.sh"
awk 'BEGIN { for (i=4000; i<=4104; i++) print "TF-" i }' > "$tmp/pane"
cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  'pane read') cat "$OVERFLOW_TMP/pane" ;;
  'pane get') printf '%s\n' '{"result":{"pane":{"terminal_id":"source-terminal"}}}' ;;
  'plugin pane')
    [ "$3" = open ] || exit 1
    for arg do
      case "$arg" in HERDR_VIEWER_CANDIDATES=*) printf '%s\n' "${arg#HERDR_VIEWER_CANDIDATES=}" > "$OVERFLOW_TMP/handoff";; esac
    done
    printf '%s\n' '{"result":{"plugin_pane":{"pane":{"pane_id":"viewer-pane","terminal_id":"viewer-terminal"}}}}'
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/twg" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$OVERFLOW_TMP/requests"
while [ "$1" != get ]; do shift; done
shift
keys=
while [ "$#" -gt 0 ]; do
  case "$1" in --*) break;; esac
  keys="${keys}${1}
"
  shift
done
if [ "${1:-}" = --comments ]; then
  printf '%s\n' '{"data":[{"key":"TF-4000","summary":"Older issue preview","status":{"name":"To Do"},"description":"Lazy detail loaded"}]}'
else
  printf '%s' "$keys" | jq -Rn '{data: [inputs | {key: ., summary: "Recent issue", status: {name: "To Do"}}]}'
fi
EOF
cat > "$tmp/bin/fzf" <<'EOF'
#!/bin/sh
[ "${1:-}" = --help ] && exit 0
cat > "$OVERFLOW_TMP/picker"
sh "$DIR/viewer-preview.sh" TF-4000 > "$OVERFLOW_TMP/preview"
EOF
chmod 700 "$tmp/bin/"*
export OVERFLOW_TMP="$tmp" PATH="$tmp/bin:$PATH" HERDR_BIN_PATH="$tmp/bin/herdr" TWG_BIN_PATH="$tmp/bin/twg"
export HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state" HERDR_PLUGIN_ID=jira-peek HERDR_PANE_ID=source-pane NO_COLOR=1
unset HERDR_SOCKET_PATH HERDR_PLUGIN_CONTEXT_JSON HERDR_VIEWER_CANDIDATES VIEWER_STATE_DIR VIEWER_FZF_SOCKET VIEWER_COORDINATOR_PID HERDR_VIEWER_SOURCE_PANE HERDR_VIEWER_SOURCE_TERMINAL

sh "$ROOT/scripts/peek.sh" >/dev/null
[ "$(wc -l < "$tmp/handoff" | tr -d ' ')" = 105 ]
[ "$(tail -n 1 "$tmp/handoff")" = TF-4000 ]
printf '%s\n' 'ok - scan and pane handoff retain keys beyond 20 and 100'

HERDR_VIEWER_CANDIDATES=$(cat "$tmp/handoff") sh "$ROOT/scripts/viewer.sh" >/dev/null
[ "$(wc -l < "$tmp/picker" | tr -d ' ')" = 105 ]
awk -F '\t' '$1 == "TF-4000" && $2 ~ /preview on select/ { found=1 } END { exit !found }' "$tmp/picker"
grep -Fq 'Lazy detail loaded' "$tmp/preview"
awk '/--fields/ { for (i=1;i<=NF;i++) if ($i ~ /^TF-[0-9]+$/) n++ } END { exit n != 20 }' "$tmp/requests"
[ "$(wc -l < "$tmp/requests" | tr -d ' ')" = 2 ]
printf '%s\n' 'ok - picker retains all keys, preloads only 20, and lazily previews the older key'
if [ -n "$real_fzf" ]; then
  env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_COMMAND -u FZF_DEFAULT_OPTS_FILE "$real_fzf" --delimiter '\t' --with-nth 2 --filter TF-4000 < "$tmp/picker" > "$tmp/matches"
  [ "$(cut -f1 "$tmp/matches")" = TF-4000 ]
  printf '%s\n' 'ok - real fzf finds the older key by exact key'
fi

cp "$tmp/handoff" "$tmp/viewer/candidates"
export VIEWER_STATE_DIR="$tmp/viewer" HERDR_VIEWER_SOURCE_PANE=source-pane HERDR_VIEWER_SOURCE_TERMINAL=source-terminal
unset VIEWER_METADATA_MODE
sh "$ROOT/scripts/viewer-rescan.sh"
cmp "$tmp/handoff" "$tmp/viewer/candidates"
grep -Fqx 'Rescanned: 105 issues' "$tmp/viewer/status"
[ "$(wc -l < "$tmp/requests" | tr -d ' ')" = 2 ]
printf '%s\n' 'ok - rescan retains every key without extra Jira requests'

# Refresh can enrich an older key's row without changing the searchable list.
VIEWER_NOTIFY=0 sh "$ROOT/scripts/viewer-fetch.sh" --refresh TF-4000
sh "$ROOT/scripts/viewer-rows.sh" > "$tmp/refreshed"
[ "$(wc -l < "$tmp/refreshed" | tr -d ' ')" = 105 ]
awk -F '\t' '$1 == "TF-4000" && $2 ~ /To Do.*Recent issue/ { found=1 } END { exit !found }' "$tmp/refreshed"
[ "$(wc -l < "$tmp/requests" | tr -d ' ')" = 3 ]
printf '%s\n' 'ok - refreshing an older key loads its searchable status and summary'
