#!/bin/sh
# Offline REST transport coverage using fictional Jira responses.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-rest.XXXXXX")
trap 'rm -rf "$T"' 0 1 2 15
mkdir -p "$T/bin" "$T/config" "$T/state"
mkdir -p "$T/viewer/rows" "$T/viewer/failed"
printf '%s\n' 'machine jira.example.test login fictional password fictional' > "$T/netrc"
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
out=; url=; code=${FAKE_HTTP:-200}
[ "$1" = -q ] || exit 99
printf '%s\n' "$*" >> "${FAKE_LOG:?}"
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; -w) shift ;; --netrc-file|-H|--connect-timeout|--max-time|--proto|--max-redirs|--data-binary) shift ;; http://*|https://*) url=$1 ;; esac
  shift
done
case "$url" in
  */bulkfetch) body='{"issues":[{"key":"ABC-123","fields":{"summary":"A summary","status":{"name":"Open"},"assignee":{"displayName":"Fictional User"},"updated":"2026-01-01"}}]}' ;;
  */issue/ABC-123?fields=*) body='{"key":"ABC-123","fields":{"summary":"A summary","status":{"name":"Open"},"assignee":{"displayName":"Fictional User"},"updated":"2026-01-01","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]}}}' ;;
  */comment?startAt=0*) body='{"startAt":0,"maxResults":2,"total":3,"comments":[{"id":"1","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Fictional User"}},{"id":"2","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Another User"}}]}' ;;
  */comment?startAt=2*) body='{"startAt":2,"maxResults":2,"total":3,"comments":[{"id":"3","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Fictional User"}}]}' ;;
  *) body='{"error":"fictional"}' ;;
esac
case "$url:${FAKE_DOCUMENT:-}" in
  *bulkfetch:controls) body='{"issues":[{"key":"ABC-123","fields":{"summary":"A\u001bsummary\nline","status":{"name":"Op\ten"}}}]}' ;;
  *fields=*:missing-summary) body='{"key":"ABC-123","fields":{"status":{"name":"Open"},"assignee":{"displayName":"Fictional User"},"updated":"2026-01-01","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]}}}' ;;
  *fields=*:null-summary) body='{"key":"ABC-123","fields":{"summary":null,"status":{"name":"Open"},"assignee":{"displayName":"Fictional User"},"updated":"2026-01-01","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]}}}' ;;
  *fields=*:wrong-key) body='{"key":"ABC-999","fields":{}}' ;;
  *fields=*:malformed) body='<html>FICTIONAL_RAW_SENTINEL</html>' ;;
  *fields=*:multiple) body="$body$body" ;;
  *comment?startAt=0*:multiple-pages) body="$body$body" ;;
  *comment?startAt=0*:empty-page) body='{"startAt":0,"maxResults":100,"total":3,"comments":[]}' ;;
esac
if [ -n "${FAKE_FAILURE:-}" ]; then
  printf '%s' 'FICTIONAL_RAW_SENTINEL' > "$out"
  printf '%s\n' 'FICTIONAL_RAW_SENTINEL' >&2
  [ "$FAKE_FAILURE" = network ] && exit 7
else
  printf '%s' "$body" > "$out"
fi
printf '%s' "$code"
EOF
chmod 700 "$T/bin/curl"
run() { env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" CURL_BIN_PATH=curl TWG_LOG="$T/twg.log" FAKE_LOG="$T/curl.log" FAKE_HTTP="${1:-200}" FAKE_FAILURE="${2:-}" FAKE_DOCUMENT="${3:-}" sh "$ROOT/scripts/fetch.sh" ABC-123; }
assert_clean() {
  [ -z "$(find "$T/state" -maxdepth 1 \( -name '.rest-*' -o -name '.twg-*' -o -name '.issue-*' \) -print)" ] || { echo 'request temporary data remained' >&2; exit 1; }
  ! grep -R FICTIONAL_RAW_SENTINEL "$T/state" "$T/failure-output" >/dev/null 2>&1 || { echo 'raw response or stderr retained' >&2; exit 1; }
}
row=$(run) || { echo 'REST fetch failed' >&2; exit 1; }
expected_row=$(printf 'ABC-123\tOpen\tA summary')
[ "$row" = "$expected_row" ] || { echo 'bad metadata row' >&2; exit 1; }
file="$T/state/cache/ABC-123.json"
jq -e '(.key == "ABC-123" and (.comments|length) == 3 and .description.type == "doc" and .assignee.displayName == "Fictional User")' "$file" >/dev/null
before=$(wc -l < "$T/curl.log")
run >/dev/null
[ "$(wc -l < "$T/curl.log")" = "$before" ] || { echo 'fresh REST cache made a request' >&2; exit 1; }
if grep -R 'TWG' "$T/state" >/dev/null 2>&1; then echo 'REST emitted TWG diagnostic' >&2; exit 1; fi
printf '%s\n' ABC-123 > "$T/viewer/candidates"
env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" CURL_BIN_PATH=curl FAKE_LOG="$T/curl.log" VIEWER_STATE_DIR="$T/viewer" sh "$ROOT/scripts/viewer-fetch.sh" --all "$T/viewer/candidates"
grep -q 'bulkfetch' "$T/curl.log" || { echo 'REST metadata bulkfetch missing' >&2; exit 1; }
grep -q '^ABC-123.*Open.*A summary' "$T/viewer/rows/ABC-123" || { echo 'REST metadata row missing' >&2; exit 1; }
env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/state" CURL_BIN_PATH=curl FAKE_LOG="$T/curl.log" FAKE_DOCUMENT=controls VIEWER_STATE_DIR="$T/viewer" sh "$ROOT/scripts/viewer-fetch.sh" --all "$T/viewer/candidates"
[ "$(cat "$T/viewer/rows/ABC-123")" = "$(printf 'ABC-123\tOp en\tA summary line')" ] || { echo 'REST metadata control characters leaked' >&2; exit 1; }
cat > "$T/bin/twg" <<'EOF'
#!/bin/sh
case " $* " in *' whoami '*) printf '%s\n' '{"accountId":"fictional-user"}'; exit 0 ;; esac
printf '%s\n' invoked >> "${TWG_LOG:?}"
twg_body='{"key":"ABC-123","summary":"A summary","status":{"name":"Open"},"assignee":{"displayName":"Fictional User"},"updated":"2026-01-01","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"comments":[{"id":"1","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Fictional User"}},{"id":"2","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Another User"}},{"id":"3","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Fictional preview body"}]}]},"author":{"displayName":"Fictional User"}}]}'
case "${FAKE_DOCUMENT:-}" in
  missing-summary) printf '%s\n' "$twg_body" | jq 'del(.summary)' ;;
  null-summary) printf '%s\n' "$twg_body" | jq '.summary = null' ;;
  *) printf '%s\n' "$twg_body" ;;
esac
EOF
chmod 700 "$T/bin/twg"
printf '%s\n' "JIRA_BACKEND='twg'" "JIRA_SITE='fictional-site'" >> "$T/config/config.sh"
env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/twg-state" TWG_BIN_PATH=twg TWG_LOG="$T/twg.log" NO_COLOR=1 COLUMNS=100 sh "$ROOT/scripts/render.sh" ABC-123 > "$T/twg-render"
sed "s/JIRA_BACKEND='twg'/JIRA_BACKEND='rest'/" "$T/config/config.sh" > "$T/rest-config"
mkdir -p "$T/rest-config-dir"
cp "$T/rest-config" "$T/rest-config-dir/config.sh"
env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/rest-config-dir" HERDR_PLUGIN_STATE_DIR="$T/rest-state" TWG_BIN_PATH=twg CURL_BIN_PATH=curl FAKE_LOG="$T/curl.log" NO_COLOR=1 COLUMNS=100 sh "$ROOT/scripts/render.sh" ABC-123 > "$T/rest-render"
cmp "$T/twg-render" "$T/rest-render" || { echo 'REST/TWG render parity failed' >&2; exit 1; }
for document in missing-summary null-summary; do
  env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/config" HERDR_PLUGIN_STATE_DIR="$T/twg-$document-state" TWG_BIN_PATH=twg TWG_LOG="$T/twg.log" FAKE_DOCUMENT="$document" NO_COLOR=1 COLUMNS=100 sh "$ROOT/scripts/render.sh" ABC-123 > "$T/twg-$document-render"
  env PATH="$T/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="$T/rest-config-dir" HERDR_PLUGIN_STATE_DIR="$T/rest-$document-state" TWG_BIN_PATH=twg CURL_BIN_PATH=curl FAKE_LOG="$T/curl.log" FAKE_DOCUMENT="$document" NO_COLOR=1 COLUMNS=100 sh "$ROOT/scripts/render.sh" ABC-123 > "$T/rest-$document-render"
  cmp "$T/twg-$document-render" "$T/rest-$document-render" || { echo "REST/TWG $document render parity failed" >&2; exit 1; }
  grep -q '(no summary)' "$T/rest-$document-render" || { echo "REST $document lost missing-summary placeholder" >&2; exit 1; }
done
printf '%s\n' "JIRA_CLOUD_ID='fictional-cloud'" >> "$T/config/config.sh"
printf '%s\n' "JIRA_BACKEND='rest'" >> "$T/config/config.sh"
rm -f "$T/state/cache/ABC-123.json"
run >/dev/null
grep -q 'api.atlassian.com/ex/jira/fictional-cloud' "$T/curl.log"
for status in 401 403 404 429 302; do
  rm -f "$T/state/cache/ABC-123.json"; : > "$T/twg.log"
  if run "$status" http > "$T/failure-output" 2>&1; then echo "HTTP $status accepted" >&2; exit 1; fi
  [ ! -e "$T/state/cache/ABC-123.json" ] || { echo "HTTP $status cached" >&2; exit 1; }
  ! grep -q FICTIONAL_RAW_SENTINEL "$T/failure-output" || { echo 'raw body leaked' >&2; exit 1; }
  [ ! -s "$T/twg.log" ] || { echo 'REST failure invoked TWG' >&2; exit 1; }
  assert_clean
done
rm -f "$T/state/cache/ABC-123.json"; : > "$T/twg.log"
if run 200 network > "$T/failure-output" 2>&1; then echo 'network failure accepted' >&2; exit 1; fi
[ ! -s "$T/twg.log" ] || { echo 'network failure invoked TWG' >&2; exit 1; }
! grep -q FICTIONAL_RAW_SENTINEL "$T/failure-output" || { echo 'network raw stderr leaked' >&2; exit 1; }
assert_clean
for document in wrong-key malformed multiple multiple-pages empty-page; do
  if run 200 '' "$document" > "$T/failure-output" 2>&1; then echo "invalid $document response accepted" >&2; exit 1; fi
  [ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'invalid response cached' >&2; exit 1; }
  assert_clean
done
before=$(wc -l < "$T/curl.log")
chmod 644 "$T/netrc"
if run > "$T/failure-output" 2>&1; then echo 'public credentials accepted' >&2; exit 1; fi
[ "$(wc -l < "$T/curl.log")" = "$before" ] || { echo 'unsafe credentials sent a request' >&2; exit 1; }
chmod 600 "$T/netrc"
printf '%s\n' 'CACHE_TTL_MIN=0' >> "$T/config/config.sh"
run >/dev/null
[ ! -e "$T/state/cache/ABC-123.json" ] || { echo 'TTL zero created durable REST cache' >&2; exit 1; }
assert_clean
echo 'ok - REST parity, metadata, pagination, routing, cache, safe failures, and cleanup'
