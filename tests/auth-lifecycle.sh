#!/bin/sh
# shellcheck disable=SC2016,SC2030,SC2031 # Child-shell fixture expressions are intentionally literal.
# Offline connection identity and cache lifecycle tests with fictional data.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-auth.XXXXXX")
trap 'rm -rf "$T"' 0 1 2 15
mkdir -p "$T/bin" "$T/config" "$T/state/cache"
printf '%s\n' 'machine jira.example.test login fictional password token-one' > "$T/netrc"
chmod 600 "$T/netrc"
cat > "$T/config/config.sh" <<EOF
JIRA_BASE='https://jira.example.test'
JIRA_PROJECTS='ABC'
JIRA_BACKEND='rest'
JIRA_NETRC_FILE='$T/netrc'
CACHE_TTL_MIN=10
MAX_CANDIDATES=20
EOF
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
case " $* " in *' --unix-socket '*) printf '%s\n' "$*" > "$UI_LOG"; exit 0 ;; esac
out=; url=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -w|--netrc-file|-H|--connect-timeout|--max-time|--proto|--max-redirs|--data-binary) shift ;; https://*) url=$1 ;; esac
  shift
done
case "$url" in */issue/*comment*) body='{"startAt":0,"maxResults":100,"total":0,"comments":[]}' ;; */issue/*) body='{"key":"ABC-123","fields":{"summary":"Fictional","status":{"name":"Open"},"description":null}}' ;; *) body='{"issues":[]}' ;; esac
if [ -n "${BLOCK_FILE:-}" ] && printf '%s' "$url" | grep -q '/issue/ABC-123?fields='; then
  : > "${BLOCK_STARTED:?}"
  while [ ! -e "$BLOCK_FILE" ]; do sleep 0.02; done
fi
printf '%s' "$body" > "$out"; printf '%s' "${FAKE_HTTP:-200}"
EOF
chmod 700 "$T/bin/curl"
cat > "$T/bin/twg" <<'EOF'
#!/bin/sh
case " $* " in *' whoami '*)
  account=${TWG_ACCOUNT:-fictional-user}
  [ -z "${TWG_ID_FILE:-}" ] || account=$(cat "$TWG_ID_FILE")
  printf '{"accountId":"%s"}\n' "$account"; exit 0 ;; esac
if [ -n "${TWG_BLOCK_GATE:-}" ]; then
  : > "$TWG_BLOCK_GATE.started"
  while [ ! -e "$TWG_BLOCK_GATE.release" ]; do sleep 0.02; done
fi
printf '%s\n' '{"key":"ABC-123","summary":"Fictional","status":{"name":"Open"},"description":null,"comments":[]}'
EOF
chmod 700 "$T/bin/twg"
run_common() { env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" CURL_BIN_PATH=curl HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh -c '. "$1/scripts/common.sh"; printf "%s\n" "${CONNECTION_ID:-}"' sh "$ROOT"; }
run_fetch() { env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" CURL_BIN_PATH=curl BLOCK_FILE="${BLOCK_FILE:-}" BLOCK_STARTED="${BLOCK_STARTED:-}" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh "$ROOT/scripts/fetch.sh" ABC-123; }
printf '%s\n' '{"key":"ABC-123","summary":"Fictional legacy cache"}' > "$T/state/cache/ABC-123.json"
first=$(run_common);
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'unscoped legacy cache was reused' >&2; exit 1; }
 [ -n "$first" ] || { echo 'missing initial connection identity' >&2; exit 1; }
touch "$T/state/cache/ABC-123.json"
second=$(run_common); [ "$second" = "$first" ] || { echo 'stable identity changed' >&2; exit 1; }
[ -e "$T/state/cache/ABC-123.json" ] || { echo 'stable identity purged cache' >&2; exit 1; }
env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" CURL_BIN_PATH=curl HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null
[ -s "$T/state/cache/ABC-123.json" ] || { echo 'REST fetch did not publish cache' >&2; exit 1; }
printf '%s\n' 'machine jira.example.test login fictional password token-two' > "$T/netrc"
chmod 600 "$T/netrc"
third=$(run_common); [ "$third" != "$second" ] || { echo 'netrc rotation not detected' >&2; exit 1; }
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'rotated auth retained cache' >&2; exit 1; }
printf '%s\n' "JIRA_BACKEND='twg'" "JIRA_SITE='fictional-site'" >> "$T/config/config.sh"
twg_one=$(env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" TWG_BIN_PATH=twg TWG_ACCOUNT=fictional-one HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh -c '. "$1/scripts/common.sh"; printf "%s\n" "$CONNECTION_ID"' sh "$ROOT")
env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" TWG_BIN_PATH=twg TWG_ACCOUNT=fictional-one HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null
[ -s "$T/state/cache/ABC-123.json" ] || { echo 'TWG fetch did not publish cache' >&2; exit 1; }
twg_two=$(env PATH="$T/bin:$PATH" DIR="$ROOT/scripts" TWG_BIN_PATH=twg TWG_ACCOUNT=fictional-two HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" sh -c '. "$1/scripts/common.sh"; printf "%s\n" "$CONNECTION_ID"' sh "$ROOT")
[ "$twg_one" != "$twg_two" ] || { echo 'TWG account switch not detected' >&2; exit 1; }
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'TWG account switch retained cache' >&2; exit 1; }
touch "$T/state/cache/ABC-123.json"
printf '%s\n' "JIRA_PROJECTS='ABC|DEF'" >> "$T/config/config.sh"
fourth=$(run_common); [ "$fourth" != "$third" ] || { echo 'config change not detected' >&2; exit 1; }
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'config change retained cache' >&2; exit 1; }
printf '%s\n' "JIRA_BACKEND='rest'" >> "$T/config/config.sh"
rm -f "$T/state/cache/ABC-123.json" "$T/block-started" "$T/block-release"
BLOCK_FILE="$T/block-release" BLOCK_STARTED="$T/block-started" run_fetch > "$T/inflight-output" 2>&1 & inflight_pid=$!
i=0; while [ ! -e "$T/block-started" ] && [ "$i" -lt 250 ]; do sleep 0.02; i=$((i+1)); done
[ -e "$T/block-started" ] || { kill "$inflight_pid" 2>/dev/null || true; echo 'in-flight request did not start' >&2; exit 1; }
printf '%s\n' 'machine jira.example.test login fictional password token-three' > "$T/netrc"; chmod 600 "$T/netrc"
run_common >/dev/null
: > "$T/block-release"
if wait "$inflight_pid"; then echo 'auth-changed in-flight request succeeded' >&2; exit 1; fi
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'auth-changed request resurrected cache' >&2; exit 1; }
rm -f "$T/state/cache/ABC-123.json" "$T/block-started" "$T/block-release"
BLOCK_FILE="$T/block-release" BLOCK_STARTED="$T/block-started" run_fetch > "$T/inflight-output" 2>&1 & inflight_pid=$!
i=0; while [ ! -e "$T/block-started" ] && [ "$i" -lt 250 ]; do sleep 0.02; i=$((i+1)); done
[ -e "$T/block-started" ] || { kill "$inflight_pid" 2>/dev/null || true; echo 'clear-cache request did not start' >&2; exit 1; }
env HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" DIR="$ROOT/scripts" sh "$ROOT/scripts/clear-cache.sh" >/dev/null
: > "$T/block-release"
if wait "$inflight_pid"; then echo 'clear-cache in-flight request succeeded' >&2; exit 1; fi
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'clear-cache request resurrected cache' >&2; exit 1; }
# Old viewers cannot adopt a new config even when the key still exists.
old_id=$(run_common)
old_epoch=$(sed -n '2p' "$T/state/connection-context")
printf '%s\n' "JIRA_BASE='https://other.example.test'" >> "$T/config/config.sh"
if (export VIEWER_CONNECTION_ID="$old_id" VIEWER_CONNECTION_EPOCH="$old_epoch"; run_fetch) > "$T/old-viewer-output" 2>&1; then
  echo 'stale viewer adopted a different site' >&2; exit 1
fi
# Server-observed authentication rejection clears cached data for other keys.
run_common >/dev/null
printf '%s\n' '{"key":"ABC-999","summary":"Fictional cached issue"}' > "$T/state/cache/ABC-999.json"
if (export FAKE_HTTP=401; run_fetch) > "$T/revoked-output" 2>&1; then
  echo 'revoked auth was accepted' >&2; exit 1
fi
[ ! -e "$T/state/cache/ABC-999.json" ] || { echo 'observed revocation retained other cache entries' >&2; exit 1; }
grep -q 'authentication failed' "$T/revoked-output"
# Offline cache reads cannot discover remote revocation until a network probe.
run_fetch >/dev/null
(export FAKE_HTTP=401; run_fetch) >/dev/null || { echo 'documented positive TTL behavior changed' >&2; exit 1; }
# The viewer timer checks local settings only and sends an abort on rotation.
mkdir "$T/viewer"
env PATH="$T/bin:$PATH" CURL_BIN_PATH=curl DIR="$ROOT/scripts" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" UI_LOG="$T/ui-log" VIEWER_STATE_DIR="$T/viewer" VIEWER_FZF_SOCKET="$T/fake.sock" sh -c '
  . "$DIR/common.sh"
  export CONNECTION_ID CONNECTION_EPOCH CONNECTION_CONFIG_DIGEST CONNECTION_AUTH_DIGEST JIRA_BACKEND JIRA_NETRC_FILE STATE CONFIG_DIR
  export VIEWER_CONNECTION_ID="$CONNECTION_ID" VIEWER_CONNECTION_EPOCH="$CONNECTION_EPOCH"
  : > "$1"
  exec sh "$DIR/viewer-ui.sh" watch-messages
' sh "$T/ui-ready" > "$T/ui-output" 2>&1 & ui_pid=$!
i=0
while [ ! -e "$T/ui-ready" ] && [ "$i" -lt 200 ]; do sleep 0.02; i=$((i + 1)); done
[ -e "$T/ui-ready" ] || { kill "$ui_pid" 2>/dev/null || true; echo 'UI guard did not start' >&2; exit 1; }
printf '%s\n' 'machine jira.example.test login fictional password token-four' > "$T/netrc"
i=0
while kill -0 "$ui_pid" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.02; i=$((i + 1)); done
if kill -0 "$ui_pid" 2>/dev/null; then kill "$ui_pid"; echo 'UI did not close after rotation' >&2; exit 1; fi
wait "$ui_pid"
grep -q -- '-d abort' "$T/ui-log"
# A preserved cache symlink must never bypass the connection boundary.
printf '%s\n' '{"key":"ABC-123","summary":"Fictional outside cache"}' > "$T/outside"
rm -f "$T/state/cache/ABC-123.json"
ln -s "$T/outside" "$T/state/cache/ABC-123.json"
run_fetch > "$T/symlink-output"
grep -q 'Fictional outside cache' "$T/outside"
[ ! -L "$T/state/cache/ABC-123.json" ] || { echo 'cache symlink was reused' >&2; exit 1; }
if grep -q 'Fictional outside cache' "$T/symlink-output"; then echo 'external cache content was rendered' >&2; exit 1; fi
# A TWG account can change externally while a detail request is pending.
printf '%s\n' "JIRA_BACKEND='twg'" >> "$T/config/config.sh"
printf '%s\n' fictional-one > "$T/twg-account"
(export TWG_ID_FILE="$T/twg-account" TWG_BLOCK_GATE="$T/twg-gate"; run_fetch) > "$T/twg-inflight-output" 2>&1 & twg_pid=$!
i=0
while [ ! -e "$T/twg-gate.started" ] && [ "$i" -lt 250 ]; do sleep 0.02; i=$((i + 1)); done
[ -e "$T/twg-gate.started" ] || { kill "$twg_pid" 2>/dev/null || true; echo 'TWG request did not start' >&2; exit 1; }
printf '%s\n' fictional-two > "$T/twg-account"
: > "$T/twg-gate.release"
if wait "$twg_pid"; then echo 'TWG account-changed response succeeded' >&2; exit 1; fi
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'TWG account-changed response was cached' >&2; exit 1; }
# Recover interrupted initialization without touching live owners.
mkdir -p "$T/state/.connection-lock"
: > "$T/state/.connection-lock/.connection-owner.99999999.fixture"
: > "$T/state/.connection-owner.99999999.fixture"
: > "$T/state/.connection.99999999.fixture"
: > "$T/state/.identity.99999999.fixture"
: > "$T/state/.connection-owner.$$.active"
run_common >/dev/null
[ ! -e "$T/state/.connection-owner.99999999.fixture" ]
[ ! -e "$T/state/.connection.99999999.fixture" ]
[ ! -e "$T/state/.identity.99999999.fixture" ]
[ ! -d "$T/state/.connection-lock" ]
[ -e "$T/state/.connection-owner.$$.active" ]
echo 'ok - connection identity, stale viewers, revocation, and in-flight cache invalidation'
