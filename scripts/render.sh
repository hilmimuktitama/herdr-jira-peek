#!/bin/sh
# shellcheck source=scripts/common.sh
# Render one cached issue as readable text. Usage: render.sh <KEY>
set -eu
SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
RENDER_JQ="$SCRIPT_DIR/render.jq"
. "$SCRIPT_DIR/common.sh"
[ -r "$RENDER_JQ" ] || die 'render.jq is missing or unreadable'
key=${1:-}
validate_key "$key" || die 'invalid Jira issue key'
f=
cleanup() {
  [ -z "$f" ] || fetch_cleanup "$f"
  fetch_work_cleanup
}
trap cleanup 0
trap 'cleanup; trap - 0; exit 1' 1 2 15

if [ "${JIRA_PEEK_RENDER_PUBLISHED:-}" = 1 ] \
  && [ -s "$CACHE/$key.json" ] \
  && jq -s -e --arg requested_key "$key" 'length == 1 and (.[0] | type) == "object" and .[0].key == $requested_key' "$CACHE/$key.json" >/dev/null 2>&1; then
  f=$CACHE/$key.json
elif fetch "$key" >/dev/null; then
  f=$FETCHED_FILE
else
  detail=$(fetch_error_detail "$key" 2>/dev/null || printf '%s' 'TWG request failed')
  die "TWG could not read $key: $detail"
fi
canonical_url=$(issue_url "$key") || die 'could not determine the issue URL'

# FZF_PREVIEW_COLUMNS is the useful width when this is a preview. COLUMNS and
# tput keep direct and less-backed renders readable as well.
preview=false
columns=${FZF_PREVIEW_COLUMNS:-}
case "$columns" in
  ''|0*|*[!0-9]*) columns='' ;;
  *) preview=true ;;
esac
if [ -z "$columns" ]; then
  columns=${COLUMNS:-}
  case "$columns" in
    ''|0*|*[!0-9]*) columns='' ;;
  esac
fi
if [ -z "$columns" ] && command -v tput >/dev/null 2>&1; then
  columns=$(tput cols 2>/dev/null || true)
  case "$columns" in
    ''|0*|*[!0-9]*) columns='' ;;
  esac
fi
[ -n "$columns" ] || columns=80

# Leave a little room for a preview divider and its padding. A minimum of one
# keeps the splitter safe even when a very narrow value is supplied by fzf.
wrap_width=$((columns - 2))
[ "$wrap_width" -gt 0 ] || wrap_width=1

if [ -n "${NO_COLOR:-}" ]; then
  color=0
  bold=
  reset=
else
  color=1
  bold=$(printf '\033[1m')
  reset=$(printf '\033[0m')
fi

if ! rendered=$(jq -r --arg url "$canonical_url" --argjson preview "$preview" \
  -f "$RENDER_JQ" "$f" 2>/dev/null); then
  die 'could not render issue content'
fi
printf '%s\n' "$rendered" | LC_ALL=C awk -v width="$wrap_width" -v color="$color" \
     -v bold="$bold" -v reset="$reset" '
   function display_length(text,    i, ch, total, advance) {
     total = 0
     for (i = 1; i <= length(text); i++) {
       ch = substr(text, i, 1)
       if (ch == "\t") {
         advance = 8 - (total % 8)
         total += advance
       } else {
         total++
       }
     }
     return total
   }

   function fit_chars(text, limit,    i, piece) {
     if (limit < 1) return 0
     piece = ""
     for (i = 1; i <= length(text); i++) {
       piece = piece substr(text, i, 1)
       if (display_length(piece) > limit) return i - 1
     }
     return length(text)
   }

   function has_non_ascii(text) {
     return text ~ /[^\001-\177]/
   }

   function emit(text,    styled) {
     styled = text
      if (color && (NR <= 2 || text == "Description" || text ~ /^Comments \([0-9]+\)$/))
       styled = bold text reset
     printf "%s\n", styled
     output_count++
   }

   {
     line = $0
     if (line == "") {
       emit("")
       next
     }

     if (display_length(line) <= width) {
       emit(line)
       next
     }

     indent_length = 0
     while (indent_length < length(line) \
        && substr(line, indent_length + 1, 1) ~ /[ \t]/)
       indent_length++
     indent = substr(line, 1, indent_length)
     rest = substr(line, indent_length + 1)
     first_prefix = indent
     continuation_prefix = indent

     if (substr(rest, 1, 2) == "> ") {
       first_prefix = indent "> "
       continuation_prefix = first_prefix
       rest = substr(rest, 3)
      } else if (substr(rest, 1, 1) ~ /[-*+]/ \
        && substr(rest, 2, 1) ~ /[ \t]/) {
       first_prefix = indent substr(rest, 1, 2)
       continuation_prefix = indent "  "
       rest = substr(rest, 3)
     } else {
       hash_count = 0
       while (substr(rest, hash_count + 1, 1) == "#") hash_count++
      if (hash_count > 0 && substr(rest, hash_count + 1, 1) ~ /[ \t]/) {
         first_prefix = indent substr(rest, 1, hash_count + 1)
         continuation_prefix = indent
         for (i = 1; i <= hash_count + 1; i++) continuation_prefix = continuation_prefix " "
         rest = substr(rest, hash_count + 2)
       }
     }

     if (display_length(first_prefix) >= width) {
       first_prefix = ""
       continuation_prefix = ""
     } else if (display_length(continuation_prefix) >= width) {
       continuation_prefix = ""
     }

     current = first_prefix
     pending = ""
     has_content = 0
     forced_line = 0
     word = ""
     pos = 1
     while (pos <= length(rest)) {
       ch = substr(rest, pos, 1)
       if (ch ~ /[ \t]/) {
         separator = ch
         pos++
         while (pos <= length(rest) && substr(rest, pos, 1) ~ /[ \t]/) {
           separator = separator substr(rest, pos, 1)
           pos++
         }
         pending = separator
         continue
       }

       word = ch
       pos++
       while (pos <= length(rest) && substr(rest, pos, 1) !~ /[ \t]/) {
         word = word substr(rest, pos, 1)
         pos++
       }

       if (has_content && display_length(current pending word) > width) {
         emit(current)
         current = continuation_prefix
         has_content = 0
         pending = ""
       }
       if (!has_content) pending = ""

        while (length(word) > 0) {
          if (has_non_ascii(word) && \
            display_length(word) > width - display_length(current)) {
            if (display_length(word) <= width) {
              current = word
              emit(current)
            } else {
              if (has_content) current = current pending
              current = current word
              emit(current)
            }
            current = continuation_prefix
            has_content = 0
            pending = ""
            word = ""
            forced_line = 1
            continue
         }
         available = width - display_length(current)
         piece_length = fit_chars(word, available)
         if (piece_length < 1) {
           emit(current)
           current = continuation_prefix
           has_content = 0
           pending = ""
           continue
         }
         if (has_content) current = current pending
         current = current substr(word, 1, piece_length)
         word = substr(word, piece_length + 1)
         pending = ""
         has_content = 1
         if (length(word) > 0) {
           emit(current)
           current = continuation_prefix
           has_content = 0
         }
       }
     }

     if (has_content)
       emit(current)
     else if (display_length(line) > width && !forced_line)
       emit("")
   }
 '
fetch_cleanup "$f"
f=
trap - 0 1 2 15
