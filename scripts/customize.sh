#!/bin/sh
# shellcheck disable=SC1091,SC2015,SC2086 # Sources are resolved from the installed plugin root; CSV splitting is intentional.
# Offline, secret-free display preference editor.
# shellcheck source=scripts/preferences.sh
set -eu
umask 077
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/preferences.sh"
# shellcheck source=scripts/style.sh
. "$root/scripts/style.sh"
command -v jq >/dev/null 2>&1 || { printf '%s\n' 'Customize Peek: jq is required for the offline preview; run Install Peek for Jira dependencies.' >&2; exit 1; }

config_dir=${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}
config_file=$config_dir/config.sh
case "$config_dir" in ''|/|.) printf '%s\n' 'Customize Peek: refusing an unsafe config directory.' >&2; exit 1 ;; esac
[ ! -L "$config_dir" ] || { printf '%s\n' 'Customize Peek: config directory must not be a symlink.' >&2; exit 1; }
[ ! -L "$config_file" ] || { printf '%s\n' 'Customize Peek: config.sh must not be a symlink.' >&2; exit 1; }
[ ! -e "$config_file" ] || [ -f "$config_file" ] || { printf '%s\n' 'Customize Peek: config.sh must be a regular file.' >&2; exit 1; }
mkdir -p "$config_dir"; chmod 700 "$config_dir"
session_dir=$(mktemp -d "$config_dir/.customize-session.XXXXXX")
session_cleanup() { rm -rf "$session_dir"; }
trap session_cleanup 0
trap 'session_cleanup; trap - 0; exit 1' 1 2 15
[ ! -e "$config_file" ] || cp "$config_file" "$session_dir/original"
jq -n '{key:"DEMO-42",summary:"Polish the onboarding panel",status:{name:"In Progress"},assignee:{displayName:"Avery Example"},reporter:{displayName:"Riley Example"},priority:{name:"High"},issuetype:{name:"Task"},project:{name:"Demo Project"},created:"2026-09-22T09:00:00Z",updated:"2026-09-22T10:00:00Z",duedate:"2026-09-30",resolution:null,labels:["onboarding","polish"],components:[{name:"Experience"}],fixVersions:[{name:"Next"}],versions:[],parent:{key:"DEMO-7"},customfield_12345:"8",description:{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"Improve first-run guidance and make the next step obvious."}]}]},comments:[{author:{displayName:"Avery Example"},created:"2026-09-22T11:00:00Z",body:{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"Looks ready for review."}]}]}}]}' > "$session_dir/preview.json"

decode_value() {
  customize_raw=$(printf '%s\n' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$customize_raw" in
    \'*\') customize_value=${customize_raw#\'}; customize_value=${customize_value%\'} ;;
    \"*\") customize_value=${customize_raw#\"}; customize_value=${customize_value%\"} ;;
    *\'*|*\"*) return 1 ;;
    *) customize_value=$customize_raw ;;
  esac
}

PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status,assignee,updated,description,comments'
READER_FIELDS='status,assignee,updated,link,description,comments'
FIELD_LABELS=
TEXT_STYLE=bold
read_preferences() {
  [ -f "$config_file" ] || return 0
  while IFS= read -r customize_line || [ -n "$customize_line" ]; do
    customize_line=$(printf '%s\n' "$customize_line" | sed 's/^[[:space:]]*//')
    case "$customize_line" in
      PICKER_FIELDS=*) decode_value "${customize_line#PICKER_FIELDS=}" || exit 1; PICKER_FIELDS=$customize_value ;;
      PREVIEW_FIELDS=*) decode_value "${customize_line#PREVIEW_FIELDS=}" || exit 1; PREVIEW_FIELDS=$customize_value ;;
      READER_FIELDS=*) decode_value "${customize_line#READER_FIELDS=}" || exit 1; READER_FIELDS=$customize_value ;;
      FIELD_LABELS=*) decode_value "${customize_line#FIELD_LABELS=}" || exit 1; FIELD_LABELS=$customize_value ;;
      COLOR_THEME=*)
        decode_value "${customize_line#COLOR_THEME=}" || exit 1
        case "$customize_value" in
          terminal|ocean|warm|mono) : ;;
          *) printf '%s\n' 'Customize Peek: COLOR_THEME is no longer supported; remove it from config.sh.' >&2; exit 1 ;;
        esac
        ;;
      TEXT_STYLE=*) decode_value "${customize_line#TEXT_STYLE=}" || exit 1; TEXT_STYLE=$customize_value ;;
    esac
  done < "$config_file"
}
read_preferences
preferences_validate_all || { printf '%s\n' 'Customize Peek: current display preferences are invalid; run doctor and fix config.sh.' >&2; exit 1; }

ask() {
  customize_label=$1; customize_current=$2
  printf '%s [%s]: ' "$customize_label" "$customize_current" >&2
  IFS= read -r customize_answer || exit 1
  [ -n "$customize_answer" ] || customize_answer=$customize_current
  [ "$customize_answer" != - ] || customize_answer=
  printf '%s' "$customize_answer"
}

ask_field_list() {
  customize_scope=$1; customize_label=$2; customize_current=$3
  while :; do
    customize_answer=$(ask "$customize_label" "$customize_current")
    if [ "$customize_answer" = '?' ]; then
      show_field_help
      continue
    fi
    [ "$customize_answer" != - ] || customize_answer=
    if preferences_validate_field_list "$customize_scope" "$customize_answer"; then
      printf '%s' "$customize_answer"
      return 0
    fi
    printf '%s\n' 'Use supported field IDs separated by commas, with no duplicates.' >&2
  done
}

ask_labels() {
  while :; do
    customize_answer=$(ask 'Field labels (field:label pairs, - clears)' "${FIELD_LABELS:--}")
    [ "$customize_answer" != - ] || customize_answer=
    if preferences_validate_labels "$customize_answer"; then
      printf '%s' "$customize_answer"
      return 0
    fi
    printf '%s\n' 'Use comma-separated field:label pairs with concise labels.' >&2
  done
}

show_field_help() {
  printf '%s\n' \
    'Fields: status, assignee, reporter, priority, issuetype, project, created, updated,' \
    'duedate, resolution, labels, components, fixVersions, versions, parent, customfield_N' \
    'Picker also accepts summary; preview and reader also accept description, comments, link.' \
    'Use commas for order, - for an empty list, and ? to show this help again.' >&2
}

show_preview() {
  customize_view=$1
  case "$customize_view" in picker) customize_list=$PICKER_FIELDS ;; preview) customize_list=$PREVIEW_FIELDS ;; reader) customize_list=$READER_FIELDS ;; esac
  customize_preview_json=$(jq -Rn --arg csv "$customize_list" '$csv | split(",") | map(select(length > 0))')
  jq --arg fields "$customize_list" 'reduce ($fields | split(",")[]
    | select(startswith("customfield_"))) as $id (. ; .[$id] = 8)' \
    "$session_dir/preview.json" > "$session_dir/selected-preview.json"
  customize_preview_mode=true
  [ "$customize_view" = reader ] && customize_preview_mode=false
  peek_style
  case "$customize_view" in
    picker) customize_title='Picker preview' ;;
    preview) customize_title='Issue preview' ;;
    reader) customize_title='Reader preview' ;;
  esac
  printf '\n%s%s%s\n' "${PEEK_BOLD:-}" "$customize_title" "${PEEK_RESET:-}"
  if [ "$customize_view" = picker ]; then
    jq -L "$root/scripts" -r --arg fields "$PICKER_FIELDS" '
      include "fields";
      . as $issue | [.key] + ($fields | split(",") | map(select(length > 0)
        | . as $id | $issue | field_value($id))) | join("\t")
    ' "$session_dir/selected-preview.json" > "$session_dir/picker.tsv"
    awk -F '\t' -v kw=7 -v fields="$PICKER_FIELDS" -v labels="$FIELD_LABELS" \
      -v reset="$PEEK_RESET" -v dim="$PEEK_DIM" -v green="$PEEK_GREEN" \
      -v yellow="$PEEK_YELLOW" -v red="$PEEK_RED" \
      -f "$root/scripts/picker-format.awk" "$session_dir/picker.tsv" | cut -f2-
  else
    jq -L "$root/scripts" -r \
      --arg url 'https://jira.example.test/browse/DEMO-42' \
      --argjson preview "$customize_preview_mode" \
      --argjson selected_fields "$customize_preview_json" \
      --arg field_labels "${FIELD_LABELS:-}" \
      -f "$root/scripts/render.jq" "$session_dir/selected-preview.json" \
      > "$session_dir/rendered" || { printf '%s\n' 'Could not render the offline preview.' >&2; exit 1; }
    customize_width=${COLUMNS:-80}
    case "$customize_width" in ''|*[!0-9]*) customize_width=80 ;; esac
    [ "$customize_width" -gt 2 ] && customize_width=$((customize_width - 2)) || customize_width=1
    LC_ALL=C awk -v width="$customize_width" \
      -v style="$PEEK_STYLE" -v labels="$FIELD_LABELS" -v bold="$PEEK_BOLD" \
      -v reset="$PEEK_RESET" \
      -f "$root/scripts/text-format.awk" "$session_dir/rendered"
  fi
}

printf '%s\n' 'Customize Peek for Jira' 'Offline preview · fictional data'
while :; do
printf '\n%s\n' 'Presets: 1 balanced · 2 triage · 3 minimal · 4 current · 5 custom'
while :; do
  preset=$(ask 'Preset' '4')
  case "$preset" in
    1|balanced|2|triage|3|minimal|4|current|5|custom) break ;;
    *) printf '%s\n' 'Choose a preset number from 1 to 5.' >&2 ;;
  esac
done
case "$preset" in
  1|balanced) PICKER_FIELDS='status,summary'; PREVIEW_FIELDS='status,assignee,updated,description,comments'; READER_FIELDS='status,assignee,updated,link,description,comments' ;;
  2|triage) PICKER_FIELDS='priority,status,summary'; PREVIEW_FIELDS='status,priority,assignee,updated,description'; READER_FIELDS='status,priority,assignee,reporter,updated,description,comments,link' ;;
  3|minimal) PICKER_FIELDS='status'; PREVIEW_FIELDS='status'; READER_FIELDS='status,description,comments' ;;
  4|current) : ;;
  5|custom)
    show_field_help
    PICKER_FIELDS=$(ask_field_list picker 'Picker fields' "$PICKER_FIELDS")
    PREVIEW_FIELDS=$(ask_field_list preview 'Preview fields' "$PREVIEW_FIELDS")
    READER_FIELDS=$(ask_field_list reader 'Reader fields' "$READER_FIELDS")
    ;;
esac
FIELD_LABELS=$(ask_labels)
preferences_validate_all || { printf '%s\n' 'Invalid preferences. Nothing was saved.' >&2; exit 1; }
show_preview picker
show_preview preview
save=$(ask 'Save? (y / edit / reader / N)' 'N')
case "$save" in
  y|Y|yes|YES) break ;;
  r|R|reader) show_preview reader; save=$(ask 'Save these preferences? (y / edit / N)' 'N'); case "$save" in y|Y|yes|YES) break ;; e|E|edit) continue ;; *) printf '%s\n' 'Cancelled. Nothing was changed.'; exit 0 ;; esac ;;
  e|E|edit) continue ;;
  *) printf '%s\n' 'Cancelled. Nothing was changed.'; exit 0 ;;
esac
done

candidate_dir=$session_dir
candidate=$candidate_dir/config.sh
if [ -f "$config_file" ]; then
  awk '!/^[[:space:]]*(PICKER_FIELDS|PREVIEW_FIELDS|READER_FIELDS|FIELD_LABELS|COLOR_THEME)=/' "$config_file" > "$candidate"
else
  : > "$candidate"
fi
printf '%s\n' "PICKER_FIELDS='$PICKER_FIELDS'" "PREVIEW_FIELDS='$PREVIEW_FIELDS'" "READER_FIELDS='$READER_FIELDS'" "FIELD_LABELS='$FIELD_LABELS'" >> "$candidate"
chmod 600 "$candidate"
if [ -f "$candidate_dir/original" ]; then
  if [ -f "$config_file" ] && [ ! -L "$config_file" ] && cmp -s "$candidate_dir/original" "$config_file"; then
    :
  else
    printf '%s\n' 'Customize Peek cancelled: config.sh changed while editing; rerun customization.' >&2
    exit 1
  fi
else
  [ ! -e "$config_file" ] && [ ! -L "$config_file" ] || { printf '%s\n' 'Customize Peek cancelled: config.sh appeared while editing; rerun customization.' >&2; exit 1; }
fi
mv "$candidate" "$config_file"
printf '%s\n' 'Preferences saved. Reopen Peek for Jira to apply the new view.'
