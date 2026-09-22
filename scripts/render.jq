# ADF is rendered node-by-node so unknown attributes can never leak into output.
include "fields";
def clean_text: gsub("\r\n|\r"; "\n") | gsub("[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]"; "");
def metadata: clean_text | gsub("[\r\n\t]+"; " ");
def trim_breaks: sub("\n+$"; "");
def attrs: if (.attrs|type) == "object" then .attrs else {} end;
def children: if (type == "object" and (.content|type) == "array") then .content else [] end;
def month_name:
  . as $month
  | ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  | if ($month|type) == "number" and $month >= 1 and $month <= 12
    then .[$month - 1]
    else null
    end;
def prefix_lines($p): split("\n") | map(if length > 0 then $p + . else . end) | join("\n");

def link_label:
  (.text // (if (.attrs|type) == "object" then
      (.attrs.text // .attrs.url // .attrs.href)
    else null end) // "")
  | if type == "string" then clean_text
    elif type == "number" or type == "boolean" then tostring
    else ""
    end;
def inline:
  if . == null then ""
  elif type == "string" or type == "number" or type == "boolean" then tostring
  elif type == "array" then map(inline) | join("")
  elif type == "object" then
    if .type == "text" then
       (.text // "") as $raw_text
       | (if ($raw_text|type) == "string" then $raw_text
          elif ($raw_text|type) == "number" or ($raw_text|type) == "boolean" then ($raw_text|tostring)
          else "" end) as $text
      | ([.marks[]? | select(type == "object" and .type == "link")
          | if (.attrs|type) == "object" then (.attrs.href // .attrs.url // "") else "" end
          | select(type == "string") | clean_text] | .[0]) as $href
      | if $href and $href != $text then "\($text) (\($href))" else $text end
    elif .type == "hardBreak" then "\n"
    elif .type == "mention" then
      (attrs.text // attrs.displayName // "@mention")
      | if type == "string" then . elif type == "number" then tostring else "@mention" end
    elif .type == "emoji" then
      (attrs.text // attrs.shortName // attrs.shortcode // "")
      | if type == "string" then . elif type == "number" then tostring else "" end
    elif .type == "inlineCard" or .type == "blockCard" or .type == "link" then link_label
    elif (.content|type) == "array" then .content | map(inline) | join("")
    else "[Unsupported content]"
    end
  else tostring
  end | clean_text;

def adf:
  if . == null then ""
  elif type == "string" or type == "number" or type == "boolean" then tostring | clean_text
  elif type == "array" then map(adf) | join("")
  elif type == "object" then
    if .type == "text" or .type == "hardBreak" or .type == "mention" or .type == "emoji"
       or .type == "inlineCard" or .type == "link" then inline
    elif .type == "media" then
      ((attrs.alt // attrs.filename // attrs.name // "")
       | if type == "string" or type == "number" then tostring else "" end | clean_text) as $name
      | (if $name == "" then "[Image]"
         elif ($name|test("\\.(png|jpe?g|gif|webp|svg)$"; "i")) then "[Image: \($name)]"
         else "[Attachment: \($name)]" end) + "\n\n"
    elif .type == "mediaSingle" or .type == "mediaGroup" then
       (children | map(adf) | join(""))
    elif .type == "blockCard" then
       (inline + "\n\n")
    elif .type == "paragraph" then ((.content // [] | if type == "array" then map(adf)|join("") else "" end) + "\n\n")
    elif .type == "heading" then
      ((attrs.level // 1) | if type == "number" then ([.,1]|max|[.,6]|min|floor) else 1 end) as $level
      | (([range(0;$level)]|map("#")|join("")) + " " + (children|map(adf)|join("")) + "\n\n")
    elif .type == "bulletList" then
      ((children | map((children | map(adf)|join("")|trim_breaks)
        | prefix_lines("- ")) | join("\n")) + "\n\n")
    elif .type == "orderedList" then
      (if (attrs.order|type) == "number" then attrs.order|floor else 1 end) as $start
       | ((children | to_entries
          | map(.key as $i | ((.value | children | map(adf)|join("")|trim_breaks)
              | prefix_lines("\($start + $i). ")))
          | join("\n") + "\n\n"))
    elif .type == "blockquote" then ((children|map(adf)|join("")|trim_breaks)|prefix_lines("> "))+"\n\n"
    elif .type == "codeBlock" then ((children|map(adf)|join("")|trim_breaks)|prefix_lines("    "))+"\n\n"
    elif .type == "listItem" or .type == "doc" then (children|map(adf)|join(""))
    elif .type == "tableRow" then ((children|map(adf)|join(" | ")|trim_breaks)+"\n\n")
    elif (.content|type) == "array" then children|map(adf)|join("")
    else "[Unsupported content]"
    end
  else tostring | clean_text
  end;

def human_date:
  display_value | . as $d
  | if ($d|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$")) then
      ($d|capture("^(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?<time>[0-9]{2}:[0-9]{2})(:[0-9]{2})(\\.[0-9]+)?(?<zone>Z|[+-][0-9]{2}:?[0-9]{2})$") ) as $p
      | ($p.date[5:7]|tonumber) as $month_number
      | ($month_number|month_name) as $month
      | if $month == null then metadata
        else "\(($p.date[8:10]|tonumber)) \($month) \($p.date[0:4]), \($p.time) "
          + (if $p.zone == "Z" then "UTC"
             else (($p.zone|gsub(":";""))[0:3] + ":" + ($p.zone|gsub(":";""))[3:]) end)
        end
    else metadata end;

def selected($id): (($selected_fields // []) | index($id)) != null;
def value($id): field_raw($id);
def field_title($id): field_label($id; ($field_labels // ""));
def scalar_text($id; $raw):
  if $raw == null then
    if $id == "status" then "(unknown)"
    elif $id == "assignee" then "unassigned"
    elif $id == "summary" then "(no summary)"
    else "(not available)" end
  else
    ($raw | display_value | clean_text)
    | if . == "" then
        if $id == "status" then "(unknown)"
        elif $id == "assignee" then "unassigned"
        elif $id == "summary" then "(no summary)"
        else "(not available)" end
      else . end
  end
  | if ($id == "created" or $id == "updated" or $id == "duedate" or $id == "resolution")
    then human_date
    else metadata
    end;
def body_text($id; $raw):
  if $id == "description" then ($raw | adf | trim_breaks)
  else "" end;
def valid_comments($raw):
  if ($raw|type) == "array" then ($raw | map(select(type == "object"))) else [] end;
def configured_lines($issue; $id; $url; $description; $comments):
  if $id == "description" then
    if $description != "" then [field_title($id), $description, ""]
    else ["\(field_title($id)): (not available)"] end
  elif $id == "comments" then
    if ($comments|length) > 0 then
      ["\(field_title($id)) (\($comments|length))"]
      + ([ $comments[]
        | ((.author // "") | display_value | metadata) as $author
        | ((.created // "") | human_date) as $created
        | ((.body // (if (.fields|type) == "object" then .fields.body else null end)) | adf | trim_breaks) as $body
        | ["\($author)  \($created)", $body, ""] ] | add)
    else ["\(field_title($id)) (0)"] end
  else
    (($issue | value($id)) as $field_raw
      | (if $id == "link" then $url else $field_raw end)) as $raw
    | if ($raw|type) == "object" and (($raw.type // "") == "doc") then
        ($raw | adf | trim_breaks) as $rich
        | if $rich == "" then ["\(field_title($id)): (not available)"]
          else [field_title($id), $rich, ""] end
      else ["\(field_title($id)): \(scalar_text($id; $raw))"]
      end
  end;

# Custom layouts keep short scalar metadata together so a selected field list
# reads like a compact facts line. Explicit aliases always remain visible;
# the small set of values that are self-evident in a picker/detail line do not
# repeat Jira's stock labels.
def explicit_field_label($id): (($field_labels // "") | parse_labels | has($id));
def terse_field($id): $id == "status" or $id == "assignee" or $id == "priority";
def dense_field_value($id; $raw):
  if ($raw|type) == "object" and (($raw.type // "") == "doc") then
    ($raw | adf | trim_breaks | metadata) as $rich
    | if $rich == "" then "(not available)" else $rich end
  else
    (scalar_text($id; $raw)) as $text
    | if $text == "(not available)" then "—" else $text end
  end;
def is_rich_field($issue; $id):
  (($issue | value($id))
   | if type == "object" then ((.type // "") == "doc") else false end);
def dense_segment($issue; $id; $url):
  (($issue | value($id)) as $field
   | (if $id == "link" then $url else $field end) as $raw
   | (dense_field_value($id; $raw)) as $text
   | if explicit_field_label($id) or (terse_field($id) | not)
     then "\(field_title($id)): \($text)"
     else $text
     end);
def custom_detail_lines($fields; $issue; $url; $description; $comments):
  (reduce ($fields[]? | select(. != "key" and . != "summary")) as $id
    ({lines: [], metadata: []};
      if $id == "description" or $id == "comments" or is_rich_field($issue; $id) then
        (.metadata) as $pending
        | (.lines + (if ($pending|length) > 0 then [($pending | join(" · "))] else [] end)) as $flushed
        | {lines: ($flushed + configured_lines($issue; $id; $url; $description; $comments)), metadata: []}
      else
        .metadata += [dense_segment($issue; $id; $url)]
      end))
  | .lines + (if (.metadata|length) > 0 then [(.metadata | join(" · "))] else [] end);

. as $issue
| (($selected_fields // []) | if type == "array" then . else [] end) as $fields
| (($issue | value("key")) // "(unknown)" | tostring | metadata) as $key
| (($issue | value("status")) as $raw_status | scalar_text("status"; $raw_status)) as $status
| (($issue | value("summary")) as $raw_summary | scalar_text("summary"; $raw_summary)) as $summary
| (($issue | value("assignee")) as $raw_assignee | scalar_text("assignee"; $raw_assignee)) as $assignee
| (($issue | value("updated")) as $raw_updated_value | scalar_text("updated"; $raw_updated_value)) as $updated
| (($issue | value("updated")) | display_value | if . == "" then "(not available)" else . end | metadata) as $raw_updated
| (($issue | value("description")) as $raw_description | body_text("description"; $raw_description)) as $description
| (valid_comments(($issue | value("comments")))) as $comments
| ([ $fields[]? | select(. != "key" and . != "summary") | . as $id
    | select(explicit_field_label($id)) ] | length > 0) as $selected_label_override
| (($fields == ["status","assignee","updated","description","comments"]) and ($selected_label_override | not)) as $default_preview
| (($fields == ["status","assignee","updated","link","description","comments"]) and ($selected_label_override | not)) as $default_reader
| (($default_preview or $default_reader)) as $default_layout
| custom_detail_lines($fields; $issue; $url; $description; $comments) as $custom_lines
| [
    # Key and summary are the stable detail identity. Status is kept in the
    # title line only when the user selected it.
    (if $default_layout and selected("status") then "\($key) \u00b7 \($status)" else $key end),
    $summary,
    (if $default_layout then
       "\($assignee) \u00b7 Updated \($updated)"
     else $custom_lines[]? end),
    (if $default_reader then
       "UPDATED   \($raw_updated)",
       (($url // "") | tostring | metadata | "LINK      \(.)")
     else empty end),
    "",
    (if $default_layout then
       if $description == "" and ($comments|length) == 0 then
         "No description or comments."
       else
         (if $description != "" then field_title("description"), $description, "" else empty end),
         (if ($comments|length) > 0 then "\(field_title("comments")) (\($comments|length))" else empty end),
         (if ($comments|length) > 0 then
           ($comments[]
            | ((.author // "") | display_value | metadata) as $author
            | ((.created // "") | human_date) as $created
            | ((.body // (if (.fields|type) == "object" then .fields.body else null end)) | adf | trim_breaks) as $body
            | "\($author)  \($created)", $body, "")
          else empty end)
       end
     else empty end)
  ][]
