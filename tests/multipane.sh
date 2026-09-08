#!/bin/sh
# Independent source/viewer lifecycle tests. No Herdr server or Jira connection.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 15
mkdir "$tmp/bin" "$tmp/config" "$tmp/state"
printf '%s\n' 'JIRA_BASE="https://jira.example.test"' 'JIRA_SITE="jira-example"' 'JIRA_PROJECTS="ABC"' > "$tmp/config/config.sh"
cat > "$tmp/bin/herdr" <<'FAKE'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MULTI_ROOT/log"
case "$1 $2" in
  'pane get')
    awk -F '\t' -v pane="$3" '$1==pane {print $2}' "$MULTI_ROOT/panes" | jq -Rse 'rtrimstr("\n") | select(length>0) | {result:{pane:{terminal_id:.}}}' ;;
  'pane read') printf '%s\n' "${MULTI_KEYS-ABC-1}" ;;
  'workspace list')
    [ "${MULTI_LIST_FAIL:-0}" = 0 ] || exit 1
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"wa"},{"workspace_id":"wb"}]}}' ;;
  'pane list')
    awk -F '\t' -v w="$4" '$3==w {print $1 "\t" $2}' "$MULTI_ROOT/panes" | jq -Rs '{result:{panes:[split("\n")[] | select(length>0) | split("\t") | {pane_id:.[0],terminal_id:.[1]}]}}' ;;
  'plugin pane')
    case "$3" in
      open)
        count=$(cat "$MULTI_ROOT/count"); count=$((count + 1)); printf '%s\n' "$count" > "$MULTI_ROOT/count"
        target=; shift 3
        while [ "$#" -gt 0 ]; do
          if [ "$1" = --target-pane ]; then target=$2; fi
          shift
        done
        workspace=$(awk -F '\t' -v p="$target" '$1==p {print $3}' "$MULTI_ROOT/panes")
        printf 'v%s\ttv%s\t%s\n' "$count" "$count" "$workspace" >> "$MULTI_ROOT/panes"
        if [ "${MULTI_OPEN_GATE:-0}" = 1 ]; then
          : > "$MULTI_ROOT/started"
          while [ ! -f "$MULTI_ROOT/release" ]; do sleep 0.1; done
        fi
        printf '{"result":{"plugin_pane":{"pane":{"pane_id":"v%s","terminal_id":"tv%s"}}}}\n' "$count" "$count" ;;
      close)
        [ "${MULTI_CLOSE_FAIL:-0}" = 0 ] || exit 1
        awk -F '\t' -v p="$4" '$1!=p' "$MULTI_ROOT/panes" > "$MULTI_ROOT/new-panes"
        mv "$MULTI_ROOT/new-panes" "$MULTI_ROOT/panes" ;;
    esac ;;
  *) exit 1 ;;
esac
FAKE
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/fzf"
cp "$tmp/bin/fzf" "$tmp/bin/twg"
# shellcheck disable=SC2016 # Literal environment references belong to the fake CLI.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$MULTI_ROOT/open-url"\n' > "$tmp/bin/open"
cp "$tmp/bin/open" "$tmp/bin/xdg-open"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" MULTI_ROOT="$tmp" HERDR_BIN_PATH="$tmp/bin/herdr" TWG_BIN_PATH="$tmp/bin/twg"
export HERDR_PLUGIN_ID=jira-peek
export HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state" HERDR_SOCKET_PATH=
unset HERDR_VIEWER_SOURCE_TERMINAL HERDR_VIEWER_SOURCE_PANE VIEWER_STATE_DIR HERDR_PLUGIN_CONTEXT_JSON
printf 'a\tta\twa\nb\ttb\twa\nc\ttc\twb\n' > "$tmp/panes"
printf '0\n' > "$tmp/count"
fail() { printf 'not ok - multipane: %s\n' "$*" >&2; exit 1; }
peek() { HERDR_PANE_ID="$1" MULTI_KEYS="${2:-ABC-1}" sh "$ROOT/scripts/peek.sh" >/dev/null; }
live() { awk -F '\t' -v p="$1" '$1==p {found=1} END {exit !found}' "$tmp/panes"; }
a="$tmp/state/sources/source-ta"; b="$tmp/state/sources/source-tb"; c="$tmp/state/sources/source-tc"
peek a ABC-1
peek b ABC-2
peek c ABC-3
if ! { live v1 && live v2 && live v3; }; then fail 'opening B/C closed another viewer'; fi
[ "$(cat "$a/key")/$(cat "$b/key")/$(cat "$c/key")" = ABC-1/ABC-2/ABC-3 ] || fail 'source selections crossed'
[ "$(cat "$a/candidates")/$(cat "$b/candidates")" = ABC-1/ABC-2 ] || fail 'candidate handoffs crossed'
# Focus can change while an old viewer callback is still running.
HERDR_PANE_ID=b HERDR_VIEWER_SOURCE_TERMINAL=ta sh "$ROOT/scripts/open-browser.sh" --select ABC-4
[ "$(cat "$a/key")/$(cat "$b/key")" = ABC-4/ABC-2 ] || fail 'callback followed current focus'
HERDR_PANE_ID=a sh "$ROOT/scripts/open-browser.sh"
[ "$(cat "$tmp/open-url")" = https://jira.example.test/browse/ABC-4 ] || fail 'source browser selection'
HERDR_PANE_ID=v2 sh "$ROOT/scripts/open-browser.sh"
[ "$(cat "$tmp/open-url")" = https://jira.example.test/browse/ABC-2 ] || fail 'viewer browser selection'
# Reused pane IDs must never close an unrelated terminal. Move the actual viewer.
awk -F '\t' 'BEGIN {OFS="\t"} $1=="v1" {$1="moved-v1"; $3="wb"} {print}' "$tmp/panes" > "$tmp/new-panes"
mv "$tmp/new-panes" "$tmp/panes"
printf 'v1\tunrelated\twa\n' >> "$tmp/panes"
MULTI_LIST_FAIL=1
export MULTI_LIST_FAIL
if peek a 2>/dev/null; then fail 'lookup failure lost tracking'; fi
if ! { [ -f "$a/viewer-pane" ] && live moved-v1; }; then fail 'lookup failure touched viewer'; fi
unset MULTI_LIST_FAIL
peek a
if ! { live v1 && live v2 && live v3; }; then fail 'toggle touched unrelated terminal'; fi
if live moved-v1; then fail 'moved viewer survived toggle'; fi
[ ! -f "$a/viewer-pane" ] || fail 'toggle retained tracking'
# A source can move and still toggle its existing viewer.
awk -F '\t' 'BEGIN {OFS="\t"} $1=="b" {$1="moved-b"; $3="wb"} {print}' "$tmp/panes" > "$tmp/new-panes"
mv "$tmp/new-panes" "$tmp/panes"
export MULTI_CLOSE_FAIL=1
if peek moved-b 2>/dev/null; then fail 'close failure not reported'; fi
if ! { [ -f "$b/viewer-pane" ] && live v2; }; then fail 'close failure lost viewer'; fi
unset MULTI_CLOSE_FAIL
peek moved-b
live v3 || fail 'moved-source toggle closed C'
if live v2; then fail 'moved-source toggle failed'; fi
# Closing a viewer whose source has disappeared still works from the viewer.
awk -F '\t' '$1!="c"' "$tmp/panes" > "$tmp/new-panes"
mv "$tmp/new-panes" "$tmp/panes"
peek v3
[ ! -f "$c/viewer-pane" ] || fail 'viewer-focused toggle lost owner'
if live v3; then fail 'viewer-focused toggle failed'; fi
# Manual close leaves stale tracking; only that source gets a replacement.
peek a
peek moved-b ABC-2
av=$(sed -n '1p' "$a/viewer-pane"); bv=$(sed -n '1p' "$b/viewer-pane")
awk -F '\t' -v p="$av" '$1!=p' "$tmp/panes" > "$tmp/new-panes"
mv "$tmp/new-panes" "$tmp/panes"
peek a
live "$bv" || fail 'stale recovery touched B'
[ "$(sed -n '1p' "$a/viewer-pane")" != "$av" ] || fail 'stale recovery did not reopen'
peek a
peek moved-b
# Keyless new source must not disturb another source's viewer or state.
peek a
if HERDR_PANE_ID=moved-b MULTI_KEYS='' sh "$ROOT/scripts/peek.sh" >/dev/null 2>&1; then fail 'keyless source opened viewer'; fi
av=$(sed -n '1p' "$a/viewer-pane"); live "$av" || fail 'keyless scan closed A'
peek a
# Different-source concurrent actions serialize registry writes but both open.
MULTI_OPEN_GATE=1 HERDR_PANE_ID=a sh "$ROOT/scripts/peek.sh" > "$tmp/first.out" 2>&1 &
first=$!
attempt=0
while [ ! -f "$tmp/started" ]; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 100 ] || { : > "$tmp/release"; wait "$first" || true; fail 'open gate timeout'; }
  sleep 0.1
done
HERDR_PANE_ID=moved-b MULTI_KEYS=ABC-2 sh "$ROOT/scripts/peek.sh" > "$tmp/second.out" 2>&1 &
second=$!
: > "$tmp/release"
wait "$first" || fail 'concurrent A open'
wait "$second" || fail 'concurrent B open'
av=$(sed -n '1p' "$a/viewer-pane"); bv=$(sed -n '1p' "$b/viewer-pane")
if ! { live "$av" && live "$bv"; }; then fail 'concurrent sources did not keep two viewers'; fi
[ "$(cat "$a/candidates")/$(cat "$b/candidates")" = ABC-1/ABC-2 ] || fail 'concurrent handoffs crossed'
# Legacy state is never assigned to the wrong source or closed from it.
printf 'old-viewer\told-terminal\twa\n' >> "$tmp/panes"
printf 'old-viewer\nold-terminal\n' > "$tmp/state/viewer-pane"
if peek a 2> "$tmp/legacy-error"; then fail 'live legacy record silently ignored'; fi
grep -q 'pre-upgrade' "$tmp/legacy-error" || fail 'upgrade instructions absent'
if ! { live old-viewer && live "$av" && live "$bv"; }; then fail 'upgrade touched live viewer'; fi
peek old-viewer
[ ! -f "$tmp/state/viewer-pane" ] || fail 'legacy viewer-focused close retained record'
if ! { live "$av" && live "$bv"; }; then fail 'legacy toggle closed scoped viewers'; fi
printf 'stale\nstale-terminal\n' > "$tmp/state/viewer-pane"
peek a
[ ! -f "$tmp/state/viewer-pane" ] || fail 'stale legacy tracking retained'
live "$bv" || fail 'stale legacy cleanup touched B'
# Unsafe identity cannot escape the source registry.
printf 'bad\t../escape\twa\n' >> "$tmp/panes"
if peek bad 2>/dev/null; then fail 'unsafe source identity accepted'; fi
printf 'ok - independent source panes, callbacks, moves, concurrency, and upgrades\n'
