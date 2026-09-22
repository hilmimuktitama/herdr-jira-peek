#!/bin/sh
# End-to-end regressions for configurable display fields and visual preferences.
# shellcheck disable=SC2016 # Child-shell source expressions are intentionally literal.
# Every Jira response and identity in this file is fictional.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-preferences.XXXXXX")
trap '[ "${KEEP_TEST_TMP:-0}" = 1 ] || rm -rf "$TMP"' 0 1 2 15
BIN=$TMP/bin
CONFIG=$TMP/config
STATE=$TMP/state
mkdir -p "$BIN" "$CONFIG" "$STATE"
chmod 700 "$BIN" "$CONFIG" "$STATE"

fail() { printf 'not ok - preferences: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok - preferences: %s\n' "$1"; }

cat > "$BIN/twg" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
  printf '%s\n' 'twg version 1.2.6'
  exit 0
fi
case " $* " in
  *' whoami '*) printf '%s\n' '{"accountId":"fictional-preferences-user"}'; exit 0 ;;
  *' doctor '*) printf '%s\n' '{"ok":true}'; exit 0 ;;
esac
printf '%s\n' "$*" >> "${TWG_LOG:?}"
printf '%s\n' '{"key":"ABC-123","summary":"Fictional configurable issue","status":{"name":"In Progress"},"assignee":{"displayName":"Fictional Assignee"},"reporter":{"displayName":"Fictional Reporter"},"priority":{"name":"High"},"issuetype":{"name":"Task"},"project":{"key":"ABC"},"created":"2026-09-01T10:00:00Z","updated":"2026-09-03T12:34:56Z","duedate":"2026-09-10","resolution":null,"labels":["fictional"],"components":[{"name":"Widget"}],"fixVersions":[{"name":"Next"}],"versions":[{"name":"1.0"}],"parent":{"key":"ABC-1"},"customfield_10016":5,"description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Description fixture"}]}]},"comments":[{"author":{"displayName":"Fictional Reviewer"},"created":"2026-09-03T13:00:00Z","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Comment fixture"}]}]}}],"url":"https://jira.example.test/browse/ABC-123"}'
EOF
chmod 700 "$BIN/twg"

cat > "$CONFIG/config.sh" <<'EOF'
JIRA_BASE='https://jira.example.test'
JIRA_SITE='fictional-site'
JIRA_PROJECTS='ABC'
CACHE_TTL_MIN=10
MAX_CANDIDATES=20
PICKER_FIELDS='status,summary,customfield_10016'
PREVIEW_FIELDS='status,assignee,updated,description,comments'
READER_FIELDS='status,assignee,updated,link,description,comments'
FIELD_LABELS='customfield_10016:Points,duedate:Due'
COLOR_THEME='ocean'
TEXT_STYLE='bold'
EOF
chmod 600 "$CONFIG/config.sh"
TWG_LOG=$TMP/twg.log
: > "$TWG_LOG"
export PATH="$BIN:$PATH"
export TWG_BIN_PATH=twg
export TWG_LOG
export HERDR_PLUGIN_CONFIG_DIR="$CONFIG"
export HERDR_PLUGIN_STATE_DIR="$STATE"
export HERDR_PLUGIN_ID=jira-peek

# The preference vocabulary is shared by runtime and doctor. Check it directly
# as well as through the public commands so failures point at the contract.
if ! helper_output=$(sh -c '. "$1/scripts/preferences.sh"; preferences_defaults; printf "%s\n" "$PICKER_FIELDS" "$PREVIEW_FIELDS" "$READER_FIELDS" "$TEXT_STYLE"; preferences_validate_all' sh "$ROOT"); then
  fail 'default preferences validate'
fi
expected_defaults='status,summary
status,assignee,updated,description,comments
status,assignee,updated,link,description,comments
bold'
[ "$helper_output" = "$expected_defaults" ] || fail 'default preference values'
pass 'shared preference defaults and validation'

if sh -c '. "$1/scripts/preferences.sh"; preferences_validate_field_list picker "status,status"' sh "$ROOT"; then
  fail 'duplicate picker fields accepted'
fi
if sh -c '. "$1/scripts/preferences.sh"; preferences_validate_field_list preview "status,not_a_jira_field"' sh "$ROOT"; then
  fail 'unknown detail field accepted'
fi
if sh -c '. "$1/scripts/preferences.sh"; preferences_validate_text_style italic' sh "$ROOT"; then
  fail 'unknown text style accepted'
fi
if sh -c '. "$1/scripts/preferences.sh"; preferences_validate_labels "status:One,status:Two"' sh "$ROOT"; then
  fail 'duplicate field labels accepted'
fi
pass 'invalid field lists, labels, and text styles rejected'

# An already-open viewer must not reinterpret rows after its config changes.
# The row fixture deliberately uses the old status,summary order; a new
# priority,status config must fail closed while the inherited viewer digest is
# present. A fresh viewer has no inherited digest and accepts the new order.
VIEWER_CONFIG=$TMP/viewer-config
VIEWER_STATE=$TMP/viewer-state
mkdir -p "$VIEWER_CONFIG" "$VIEWER_STATE/rows" "$VIEWER_STATE/failed"
chmod 700 "$VIEWER_CONFIG" "$VIEWER_STATE"
cat > "$VIEWER_CONFIG/config.sh" <<'EOF'
JIRA_BASE='https://jira.example.test'
JIRA_SITE='fictional-site'
JIRA_PROJECTS='ABC'
PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status'
READER_FIELDS='status'
EOF
chmod 600 "$VIEWER_CONFIG/config.sh"
viewer_digest=$(env DIR="$ROOT/scripts" HERDR_PLUGIN_CONFIG_DIR="$VIEWER_CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_STATE" \
  sh -c '. "$1/scripts/common.sh"; printf "%s" "$CONNECTION_CONFIG_DIGEST"' sh "$ROOT") \
  || fail 'viewer digest fixture setup'
printf '%s\n' 'ABC-123' > "$VIEWER_STATE/candidates"
printf '%s\t%s\t%s\n' 'ABC-123' 'In Progress' 'Old fictional summary' > "$VIEWER_STATE/rows/ABC-123"
printf '%s\n' "PICKER_FIELDS='priority,status'" >> "$VIEWER_CONFIG/config.sh"
if viewer_stale_output=$(env -u VIEWER_CONFIG_DIGEST \
  HERDR_PLUGIN_CONFIG_DIR="$VIEWER_CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_STATE" \
  VIEWER_CONFIG_DIGEST="$viewer_digest" VIEWER_STATE_DIR="$VIEWER_STATE" \
  CANDIDATES_FILE="$VIEWER_STATE/candidates" NO_COLOR=1 \
  sh "$ROOT/scripts/viewer-rows.sh" 2>"$TMP/viewer-stale-error" ); then
  fail 'open viewer accepted changed field order'
fi
[ -z "$viewer_stale_output" ] || fail 'open viewer emitted stale rows after config change'
grep -Fqx 'jira-peek: Configuration changed; close and reopen Peek.' "$TMP/viewer-stale-error" \
  || fail 'open viewer gave no reopen guidance'
printf '%s\t%s\t%s\n' 'ABC-123' 'High' 'In Progress' > "$VIEWER_STATE/rows/ABC-123"
viewer_fresh_output=$(env -u VIEWER_CONFIG_DIGEST \
  HERDR_PLUGIN_CONFIG_DIR="$VIEWER_CONFIG" HERDR_PLUGIN_STATE_DIR="$VIEWER_STATE" \
  VIEWER_STATE_DIR="$VIEWER_STATE" CANDIDATES_FILE="$VIEWER_STATE/candidates" NO_COLOR=1 \
  sh "$ROOT/scripts/viewer-rows.sh") || fail 'fresh viewer rejected new field order'
case "$viewer_fresh_output" in
  *'High'*'In Progress'*) pass 'open viewer fails closed while fresh viewer accepts new field order' ;;
  *) fail 'fresh viewer rendered the configured field order' ;;
esac

# The customizer is offline and must preserve connection settings while making
# save/cancel decisions. Keep this flow separate from the transport fixture so
# each case starts from a known config snapshot.
CUSTOM_CONFIG=$TMP/custom-config
CUSTOM_STATE=$TMP/custom-state
mkdir -p "$CUSTOM_CONFIG" "$CUSTOM_STATE"
chmod 700 "$CUSTOM_CONFIG" "$CUSTOM_STATE"
cat > "$CUSTOM_CONFIG/config.sh" <<'EOF'
JIRA_BASE='https://jira.example.test'
JIRA_SITE='fictional-site'
JIRA_PROJECTS='ABC'
PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status,assignee,updated,description,comments'
READER_FIELDS='status,assignee,updated,link,description,comments'
FIELD_LABELS='status:State'
TEXT_STYLE='bold'
EOF
chmod 600 "$CUSTOM_CONFIG/config.sh"
customize_run() {
  env HERDR_PLUGIN_CONFIG_DIR="$CUSTOM_CONFIG" HERDR_PLUGIN_STATE_DIR="$CUSTOM_STATE" \
    sh "$ROOT/scripts/customize.sh"
}
custom_before=$(mktemp "$TMP/custom-before.XXXXXX")
cp "$CUSTOM_CONFIG/config.sh" "$custom_before"
printf '%s\n' 1 - y | customize_run > "$TMP/custom-save-output" 2>&1 \
  || fail 'customizer balanced save'
grep -Fqx "PICKER_FIELDS='status,summary'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer saved picker fields'
if grep -q '^COLOR_THEME=' "$CUSTOM_CONFIG/config.sh"; then fail 'customizer retained deprecated color theme'; fi
grep -Fqx "TEXT_STYLE='bold'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer preserved advanced text style'
grep -Fqx "JIRA_SITE='fictional-site'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer preserved connection settings'
if grep -Eq 'Reader preview|Color theme|Text style' "$TMP/custom-save-output"; then
  fail 'customizer showed optional reader or deprecated appearance prompts by default'
fi
pass 'customizer saves fields, strips deprecated palette, and preserves text style'

cp "$CUSTOM_CONFIG/config.sh" "$custom_before"
printf '%s\n' 2 - n | customize_run > "$TMP/custom-cancel-output" 2>&1 \
  || fail 'customizer cancel flow'
cmp -s "$custom_before" "$CUSTOM_CONFIG/config.sh" || fail 'customizer cancel changed config'
pass 'customizer cancel preserves config'

cp "$custom_before" "$CUSTOM_CONFIG/config.sh"
if printf '%s' '' | customize_run > "$TMP/custom-eof-output" 2>&1; then
  fail 'customizer accepted EOF as save'
fi
cmp -s "$custom_before" "$CUSTOM_CONFIG/config.sh" || fail 'customizer EOF changed config'
pass 'customizer EOF leaves config untouched'

printf '%s\n' 1 - edit 3 - y | customize_run > "$TMP/custom-edit-output" 2>&1 \
  || fail 'customizer edit loop'
grep -Fqx "PICKER_FIELDS='status'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer edit loop picker value'
if grep -q '^COLOR_THEME=' "$CUSTOM_CONFIG/config.sh"; then fail 'customizer edit loop retained deprecated palette'; fi
grep -Fqx "TEXT_STYLE='bold'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer edit loop text style changed'
pass 'customizer edit loop reopens preset selection'

printf '%s\n' \
  5 \
  'status,status' 'status,customfield_10016' \
  'status,,updated' 'status,priority' \
  'status,unknown' 'status,priority,description' \
  'status:State,customfield_10016:Points' y \
  | customize_run > "$TMP/custom-custom-output" 2>&1 \
  || fail 'customizer custom field flow'
grep -Fqx "PICKER_FIELDS='status,customfield_10016'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer custom picker list'
grep -Fqx "PREVIEW_FIELDS='status,priority'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer custom preview list'
grep -Fqx "READER_FIELDS='status,priority,description'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer custom reader list'
grep -Fqx "FIELD_LABELS='status:State,customfield_10016:Points'" "$CUSTOM_CONFIG/config.sh" || fail 'customizer custom labels'
pass 'customizer retries invalid input and saves ordered custom lists'

# Reader output is an optional review step after the default picker/preview
# review. It must not force another field-edit form or alter the saved lists.
cp "$CUSTOM_CONFIG/config.sh" "$custom_before"
printf '%s\n' 4 '' reader y | customize_run > "$TMP/custom-reader-output" 2>&1 \
  || fail 'customizer optional reader review'
cmp -s "$custom_before" "$CUSTOM_CONFIG/config.sh" || fail 'reader review changed saved config'
grep -Fq 'Reader preview' "$TMP/custom-reader-output" || fail 'reader review did not render reader preview'
pass 'customizer keeps reader preview optional and repeatable'

# A change made while the editor is validating must abort the save. The fake
# cmp mutates only this fictional test config immediately before comparison.
RACE_BIN=$TMP/race-bin
mkdir -p "$RACE_BIN"
cat > "$RACE_BIN/cmp" <<'EOF'
#!/bin/sh
printf '%s\n' '# concurrent fictional edit' >> "$CUSTOM_CONFIG/config.sh"
exec /usr/bin/cmp "$@"
EOF
chmod 700 "$RACE_BIN/cmp"
cp "$custom_before" "$CUSTOM_CONFIG/config.sh"
if printf '%s\n' 1 - y | env PATH="$RACE_BIN:$PATH" CUSTOM_CONFIG="$CUSTOM_CONFIG" \
  HERDR_PLUGIN_CONFIG_DIR="$CUSTOM_CONFIG" HERDR_PLUGIN_STATE_DIR="$CUSTOM_STATE" \
  sh "$ROOT/scripts/customize.sh" > "$TMP/custom-race-output" 2>&1; then
  fail 'customizer accepted concurrent config edit'
fi
grep -q 'config.sh changed while editing' "$TMP/custom-race-output" || fail 'customizer race diagnostic'
grep -q 'concurrent fictional edit' "$CUSTOM_CONFIG/config.sh" || fail 'customizer race preserved concurrent edit'
pass 'customizer aborts on concurrent config edits'

# Deleting the active config during the final validation is also a conflict;
# the editor must not recreate or overwrite that path.
DELETE_BIN=$TMP/delete-bin
mkdir -p "$DELETE_BIN"
cat > "$DELETE_BIN/cmp" <<'EOF'
#!/bin/sh
rm -f "$CUSTOM_CONFIG/config.sh"
exec /usr/bin/cmp "$@"
EOF
chmod 700 "$DELETE_BIN/cmp"
cp "$custom_before" "$CUSTOM_CONFIG/config.sh"
if printf '%s\n' 1 - y | env PATH="$DELETE_BIN:$PATH" CUSTOM_CONFIG="$CUSTOM_CONFIG" \
  HERDR_PLUGIN_CONFIG_DIR="$CUSTOM_CONFIG" HERDR_PLUGIN_STATE_DIR="$CUSTOM_STATE" \
  sh "$ROOT/scripts/customize.sh" > "$TMP/custom-delete-output" 2>&1; then
  fail 'customizer recreated deleted config'
fi
grep -q 'config.sh changed while editing' "$TMP/custom-delete-output" || fail 'customizer deletion diagnostic'
[ ! -e "$CUSTOM_CONFIG/config.sh" ] || fail 'customizer deletion conflict recreated config'
pass 'customizer aborts when config is deleted during editing'

# Doctor must parse and report the new settings without exposing fixture data.
doctor_output=$(TWG_BIN_PATH=twg sh "$ROOT/scripts/doctor.sh" 2>&1 || true)
case "$doctor_output" in
  *'PICKER_FIELDS'*'PREVIEW_FIELDS'*'READER_FIELDS'*'TEXT_STYLE'*) pass 'doctor reports display preferences' ;;
  *) fail 'doctor reports display preferences' ;;
esac
case "$doctor_output" in *'FAIL'* ) fail 'valid preferences rejected by doctor' ;; esac

for bad_line in \
  "PICKER_FIELDS='status,unknown'" \
  "PREVIEW_FIELDS='status,,updated'" \
  "FIELD_LABELS='status:One,status:Two'" \
  "COLOR_THEME='neon'" \
  "TEXT_STYLE='italic'"; do
  bad_config=$TMP/bad-config
  mkdir -p "$bad_config"
  cp "$CONFIG/config.sh" "$bad_config/config.sh"
  printf '%s\n' "$bad_line" >> "$bad_config/config.sh"
  if env HERDR_PLUGIN_CONFIG_DIR="$bad_config" HERDR_PLUGIN_STATE_DIR="$TMP/bad-state" \
    TWG_BIN_PATH=twg sh "$ROOT/scripts/doctor.sh" > "$TMP/doctor-bad" 2>&1; then
    fail "doctor accepted $bad_line"
  fi
  case "$(cat "$TMP/doctor-bad")" in *'PICKER_FIELDS'*|*'PREVIEW_FIELDS'*|*'FIELD_LABELS'*|*'COLOR_THEME'*|*'TEXT_STYLE'*) : ;; *) fail "doctor diagnostic for $bad_line" ;; esac
  rm -rf "$bad_config" "$TMP/bad-state"
done
pass 'doctor rejects invalid display preferences'

# A non-default projection must be reflected in transport arguments. A second
# projection without comments must omit the comments flag entirely.
if ! fetch_output=$(sh "$ROOT/scripts/fetch.sh" ABC-123); then
  fail 'custom projection fetch'
fi
case "$(sed -n '$p' "$TWG_LOG")" in
  *'jira workitem get ABC-123 --fields '* ) : ;;
  *) fail "custom projection uses explicit fields: $(sed -n '1p' "$TWG_LOG")" ;;
esac
case "$(sed -n '$p' "$TWG_LOG")" in
  *'customfield_10016'* ) : ;;
  *) fail 'custom projection includes configured custom field' ;;
esac
case "$(sed -n '$p' "$TWG_LOG")" in
  *'--comments'* ) : ;;
  *) fail 'comments requested when detail view selects comments' ;;
esac
[ "$fetch_output" = "$(printf 'ABC-123\tIn Progress\tFictional configurable issue\t5')" ] || fail 'picker projection row remains stable'
pass 'custom field projection and comments transport'

printf '%s\n' "PREVIEW_FIELDS='status,assignee'" "READER_FIELDS='status,assignee,link'" >> "$CONFIG/config.sh"
rm -f "$STATE/cache/ABC-123.json"
: > "$TWG_LOG"
sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'comments-disabled fetch'
case "$(sed -n '1p' "$TWG_LOG")" in
  *'--comments'*) fail 'comments flag sent when comments are disabled' ;;
  *) pass 'comments flag suppressed when comments are disabled' ;;
esac

# Request coverage belongs to the cache contract. A changed field union must
# miss the old entry and publish a new request marker; pure style changes do not.
cache_file=$STATE/cache/ABC-123.json
[ -s "$cache_file" ] || fail 'custom projection cache published'
jq -e '._peek_request | type == "string" and contains("v1:")' "$cache_file" >/dev/null \
  || fail 'cache carries request coverage marker'
before_calls=$(wc -l < "$TWG_LOG" | tr -d ' ')
printf '%s\n' "PREVIEW_FIELDS='status,priority'" >> "$CONFIG/config.sh"
sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'field coverage refresh'
after_calls=$(wc -l < "$TWG_LOG" | tr -d ' ')
[ "$after_calls" -gt "$before_calls" ] || fail 'changed field coverage reused stale cache'
printf '%s\n' "COLOR_THEME='ocean'" "TEXT_STYLE='plain'" >> "$CONFIG/config.sh"
before_calls=$(wc -l < "$TWG_LOG" | tr -d ' ')
sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'style-only cache read'
after_calls=$(wc -l < "$TWG_LOG" | tr -d ' ')
[ "$after_calls" = "$before_calls" ] || fail 'style-only preference change refetched issue'
pass 'cache request coverage tracks data fields, not style'

# Rendering must keep arbitrary control bytes out of the terminal while still
# rendering supported typed values and custom labels.
printf '%s\n' "PREVIEW_FIELDS='status,priority,customfield_10016,labels,description,comments'" >> "$CONFIG/config.sh"
sh "$ROOT/scripts/fetch.sh" ABC-123 >/dev/null || fail 'render coverage fetch'
render_request=$(jq -r '._peek_request' "$cache_file")
printf '%s\n' '{"key":"ABC-123","summary":"Safe title","status":{"name":"Done"},"priority":{"name":"High\u001b[31m"},"customfield_10016":8,"labels":["safe","fixture"],"description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"line\u0007one"}]}]},"comments":[]}' \
  | jq --arg request "$render_request" '._peek_request = $request' > "$TMP/render-cache"
mv "$TMP/render-cache" "$cache_file"
rendered=$(env JIRA_PEEK_RENDER_PUBLISHED=1 NO_COLOR=1 COLUMNS=120 FZF_PREVIEW_COLUMNS=120 sh "$ROOT/scripts/render.sh" ABC-123 2>&1) || fail "safe configurable render: $rendered"
esc=$(printf '\033')
case "$rendered" in *"$esc"*) fail 'control bytes escaped from configurable render' ;; esac
case "$rendered" in *'Safe title'*'Done'*'High'*'Points: 8'*'Labels: safe, fixture'*'lineone'*) pass 'typed values and control bytes render safely' ;; *) fail 'typed values and control bytes render safely' ;; esac

# Nested fields are authoritative even when an older flattened alias exists;
# boolean false must survive scalar extraction instead of being treated as a
# missing value. Keep this entirely in fictional cached data.
false_value=$(printf '%s\n' '{"key":"ABC-123","customfield_10016":"stale","fields":{"customfield_10016":false}}' \
  | jq -L "$ROOT/scripts" -r 'include "fields"; field_value("customfield_10016")')
[ "$false_value" = false ] || fail 'boolean false field extraction'
rich_value=$(printf '%s\n' '{"key":"ABC-123","fields":{"customfield_10016":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Rich fixture"}]}]}}}' \
  | jq -L "$ROOT/scripts" -r 'include "fields"; field_value("customfield_10016")')
[ "$rich_value" = 'Rich fixture' ] || fail 'rich custom field picker projection'
false_render=$(printf '%s\n' '{"key":"ABC-123","summary":"False fixture","fields":{"customfield_10016":false,"status":{"name":"Done"}}}' \
  | jq -L "$ROOT/scripts" -r --arg url 'https://jira.example.test/browse/ABC-123' \
      --argjson preview true --argjson selected_fields '["customfield_10016","status"]' \
      --arg field_labels 'customfield_10016:Points' -f "$ROOT/scripts/render.jq")
case "$false_render" in
  *'Points: false'*'Done'*) pass 'false and nested field precedence render safely' ;;
  *) fail 'false and nested field precedence render safely' ;;
esac

rich_render=$(printf '%s\n' '{"key":"ABC-123","summary":"Rich fixture","fields":{"status":{"name":"Done"},"customfield_10016":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"First paragraph"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"list item"}]}]}]},{"type":"paragraph","content":[{"type":"text","text":"Last paragraph"}]}]},"priority":{"name":"High"}}}' \
  | jq -L "$ROOT/scripts" -r --arg url 'https://jira.example.test/browse/ABC-123' \
      --argjson preview true --argjson selected_fields '["status","customfield_10016","priority"]' \
      --arg field_labels 'customfield_10016:Details' -f "$ROOT/scripts/render.jq")
case "$rich_render" in
  *'Done'*'Details'*'First paragraph'*'- list item'*'Last paragraph'*'High'*) pass 'rich custom fields keep labeled sections and configured order' ;;
  *) fail 'rich custom fields flattened or reordered' ;;
esac

malformed_reader=$(printf '%s\n' '{"key":"ABC-123","summary":"Malformed metadata fixture","status":{"name":"Done"},"assignee":{"displayName":"Fictional Assignee"},"updated":{"unexpected":"must-not-leak"},"comments":[{"created":{"unexpected":"must-not-leak"},"body":"Safe body"}]}' \
  | jq -L "$ROOT/scripts" -r --arg url 'https://jira.example.test/browse/ABC-123' \
      --argjson preview false --argjson selected_fields '["status","assignee","updated","link","description","comments"]' \
      --arg field_labels '' -f "$ROOT/scripts/render.jq")
case "$malformed_reader" in
  *'UPDATED   (not available)'*'Safe body'*) : ;;
  *) fail 'malformed dates and comment bodies render safely' ;;
esac
case "$malformed_reader" in *'must-not-leak'*|*'{'*) fail 'malformed reader leaked object data' ;; *) pass 'malformed dates and comment bodies render safely' ;; esac

link_render=$(printf '%s\n' '{"key":"ABC-123","summary":"Link fixture","url":"https://foreign.example.test/ABC-123","status":{"name":"Done"}}' \
  | jq -L "$ROOT/scripts" -r --arg url 'https://jira.example.test/browse/ABC-123?from=peek#details' \
      --argjson preview true --argjson selected_fields '["link","status"]' \
      --arg field_labels 'link:Open link' -f "$ROOT/scripts/render.jq")
case "$link_render" in
  *'Open link: https://jira.example.test/browse/ABC-123?from=peek#details'*) : ;;
  *) fail 'custom link uses canonical URL and preserves suffix' ;;
esac
case "$link_render" in *'foreign.example.test'*) fail 'custom link leaked cached URL' ;; esac
pass 'custom link uses canonical URL and preserves suffix'

# The shared picker formatter must honor explicit labels on default fields but
# ignore labels for fields that are not selected.
picker_default=$(printf '%s\t%s\t%s\n' 'ABC-123' 'Done' 'Fictional summary' | awk -F '\t' \
  -v kw=7 -v fields='status,summary' -v labels='customfield_10016:Points' \
  -v reset='' -v dim='' -v green='' -v yellow='' -v red='' -f "$ROOT/scripts/picker-format.awk")
case "$picker_default" in *'Done'*'Fictional summary'*'Points'*) fail 'unused picker label changed default row' ;; *) : ;; esac
picker_labeled=$(printf '%s\t%s\t%s\n' 'ABC-123' 'Done' 'Fictional summary' | awk -F '\t' \
  -v kw=7 -v fields='status,summary' -v labels='status:Stage,summary:Title' \
  -v reset='' -v dim='' -v green='' -v yellow='' -v red='' -f "$ROOT/scripts/picker-format.awk")
case "$picker_labeled" in *'Stage: Done'*'Title: Fictional summary'*) pass 'selected picker labels render in order' ;; *) fail 'selected picker labels render in order' ;; esac
# Unused aliases must not clobber the formatter's field iterator. This catches
# regressions where label parsing overwrites the outer AWK loop variable.
picker_unused_aliases=$(printf '%s\t%s\t%s\t%s\n' 'ABC-123' 'High' 'In Progress' 'Fictional summary' | awk -F '\t' \
  -v kw=7 -v fields='priority,status,summary' -v labels='customfield_10016:Points,duedate:Due' \
  -v reset='' -v dim='' -v green='' -v yellow='' -v red='' -f "$ROOT/scripts/picker-format.awk")
case "$picker_unused_aliases" in *'High'*'In Progress'*'Fictional summary'*) pass 'unused labels preserve every configured picker field' ;; *) fail 'unused labels dropped configured picker fields' ;; esac
# Exercise canonical-to-TSV projection, where @tsv used to double literal
# backslashes even though all separator/control characters were sanitized.
printf '%s\n' '{"key":"ABC-123","customfield_10016":"C:\\fictional\\path"}' > "$TMP/backslash.json"
picker_backslash=$(sh -c 'DIR="$1/scripts"; . "$DIR/common.sh"; PICKER_FIELDS=customfield_10016; picker_row "$2"' sh "$ROOT" "$TMP/backslash.json")
[ "$picker_backslash" = "$(printf 'ABC-123\t%s' 'C:\fictional\path')" ] \
  || fail 'configured picker doubled or lost backslashes'
pass 'configured picker preserves literal backslashes'

# Style controls must affect ANSI output, while NO_COLOR remains authoritative.
printf '%s\n' "TEXT_STYLE='bold'" >> "$CONFIG/config.sh"
styled=$(env -u NO_COLOR JIRA_PEEK_RENDER_PUBLISHED=1 COLUMNS=120 sh "$ROOT/scripts/render.sh" ABC-123 2>&1) || fail 'styled render'
printf '%s\n' "TEXT_STYLE='plain'" >> "$CONFIG/config.sh"
plain=$(env JIRA_PEEK_RENDER_PUBLISHED=1 NO_COLOR=1 COLUMNS=120 sh "$ROOT/scripts/render.sh" ABC-123 2>&1) || fail 'plain render'
case "$styled" in *"$esc"*) : ;; *) fail 'configured style emits ANSI' ;; esac
case "$plain" in *"$esc"*) fail 'NO_COLOR disables configured style' ;; esac
pass 'text style and NO_COLOR behavior'

# Deprecated palette assignments remain accepted for compatibility but have
# no active effect; every known legacy value matches the terminal baseline.
STYLE_BASE=$TMP/style-base
mkdir -p "$STYLE_BASE"
sed '/^[[:space:]]*COLOR_THEME=/d; /^[[:space:]]*TEXT_STYLE=/d' "$CONFIG/config.sh" > "$STYLE_BASE/config.sh"
printf '%s\n' "TEXT_STYLE='bold'" >> "$STYLE_BASE/config.sh"
env -u NO_COLOR HERDR_PLUGIN_CONFIG_DIR="$STYLE_BASE" HERDR_PLUGIN_STATE_DIR="$STATE" \
  JIRA_PEEK_RENDER_PUBLISHED=1 COLUMNS=120 sh "$ROOT/scripts/render.sh" ABC-123 > "$TMP/style-baseline" \
  || fail 'terminal style baseline render'
for legacy_palette in terminal ocean warm mono; do
  palette_dir=$TMP/style-$legacy_palette
  mkdir -p "$palette_dir"
  cp "$STYLE_BASE/config.sh" "$palette_dir/config.sh"
  printf '%s\n' "COLOR_THEME='$legacy_palette'" >> "$palette_dir/config.sh"
  env -u NO_COLOR HERDR_PLUGIN_CONFIG_DIR="$palette_dir" HERDR_PLUGIN_STATE_DIR="$STATE" \
    JIRA_PEEK_RENDER_PUBLISHED=1 COLUMNS=120 sh "$ROOT/scripts/render.sh" ABC-123 > "$TMP/style-$legacy_palette.out" \
    || fail "legacy $legacy_palette compatibility render"
  cmp -s "$TMP/style-baseline" "$TMP/style-$legacy_palette.out" \
    || fail "legacy $legacy_palette changed terminal rendering"
done
pass 'legacy palettes are ignored while text style remains active'

printf '%s\n' 'ok - preferences end-to-end coverage'
