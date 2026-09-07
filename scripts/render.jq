# ADF is rendered node-by-node so unknown attributes can never leak into output.
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
  tostring as $d
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

. as $issue | (($issue.status // "(unknown)") | if type=="object" then (.name // .displayName // "(unknown)") else tostring end | metadata) as $status
| (($issue.assignee // "unassigned") | if type=="object" then (.displayName // .name // "unassigned") else tostring end | metadata) as $assignee
| (($issue.updated // "(unknown)") | human_date) as $updated
| (($issue.updated // "(unknown)") | tostring | metadata) as $raw_updated
| (($issue.summary // "(no summary)")|tostring|metadata) as $summary
| (($issue.description|adf|trim_breaks)) as $description
| (($issue.comments // [])|if type=="array" then map(select(type == "object")) else [] end) as $comments
 | ["\($issue.key // "(unknown)") \u00b7 \($status)", $summary,
    "\($assignee) \u00b7 Updated \($updated)",
   (if ($preview // false) then empty else "UPDATED   \($raw_updated)", ("LINK      \($url // "")"|metadata) end), "",
   (if $description != "" then "Description", $description, "" else empty end),
   (if ($comments|length)>0 then "Comments (\($comments|length))" else if $description=="" then "No description or comments." else empty end end),
   (if ($comments|length)>0 then $comments[] | ((.author // "")|if type=="object" then (.displayName // .name // "") else tostring end|metadata) as $author | ((.created // "")|human_date) as $created | (.body|adf|trim_breaks) as $body | "\($author)  \($created)", $body, "" else empty end)][]
