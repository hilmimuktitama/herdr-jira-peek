# Shared Jira field lookup and presentation helpers.
#
# This file is included by render.jq and can also be included by callers that
# need to resolve a configured field from either the canonical nested shape or
# an older flattened cache entry.
module {
  "name": "jira_peek_fields"
};

def field_names:
  {
    key: "Key",
    summary: "Summary",
    status: "Status",
    assignee: "Assignee",
    reporter: "Reporter",
    priority: "Priority",
    issuetype: "Type",
    project: "Project",
    created: "Created",
    updated: "Updated",
    duedate: "Due date",
    resolution: "Resolution",
    labels: "Labels",
    components: "Components",
    fixVersions: "Fix versions",
    versions: "Affects versions",
    parent: "Parent",
    description: "Description",
    comments: "Comments",
    link: "Link"
  };

def text_value:
  if . == null then ""
  elif type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  else ""
  end;

def field_clean:
  tostring
  | gsub("\r\n|\r"; "\n")
  | gsub("[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]"; " ")
  | gsub("[\r\n\t]+"; " ");

# Turn common Jira objects into one safe display string. Unknown objects are
# intentionally reduced to a useful name/id/value instead of being dumped as
# arbitrary JSON metadata.
def display_value:
  if . == null then ""
  elif type == "string" or type == "number" or type == "boolean" then tostring
  elif type == "array" then map(display_value | select(length > 0)) | join(", ")
  elif type == "object" then
    (if .displayName != null then .displayName
     elif .name != null then .name
     elif .value != null then .value
     elif .key != null then .key
     elif .id != null then .id
     else "" end) | text_value
  else ""
  end;

# Project Atlassian Document Format to a safe one-line picker value. This is
# deliberately smaller than the reader's full renderer: recognized text nodes
# survive, while attributes, links, mentions, and unknown metadata do not.
def rich_inline:
  if . == null then ""
  elif type == "string" or type == "number" or type == "boolean" then tostring
  elif type == "array" then map(rich_inline) | join(" ")
  elif type == "object" and .type == "text" then (.text // "") | text_value
  elif type == "object" and .type == "hardBreak" then " "
  elif type == "object" and (.content|type) == "array" then (.content | map(rich_inline) | join(" "))
  else ""
  end;
def rich_value:
  if type == "object" and .type == "doc" and (.content|type) == "array"
  then (.content | map(rich_inline) | join(" "))
  else ""
  end;

# Return the requested field from the canonical {fields:{...}} shape, while
# accepting the flattened aliases used by older cached responses.
def field_raw($id):
  if $id == "key" then .key
  elif $id == "link" then
    (if .link != null then .link
     elif .url != null then .url
     elif (.fields|type) == "object" and (.fields|has("link")) then .fields.link
     elif (.fields|type) == "object" and (.fields|has("url")) then .fields.url
     else null end)
  elif ($id == "comments" or $id == "description") then
    (if (.fields|type) == "object" and (.fields|has($id)) then .fields[$id] else .[$id] end)
  elif (.fields|type) == "object" and (.fields|has($id)) then .fields[$id]
  else .[$id]
  end;

# Safe scalar form for transport/picker extraction. Description and comments
# remain intentionally empty here because they are rendered as structured
# bodies by render.jq; callers should use field_raw for those fields.
def field_value($id):
  field_raw($id)
  | if . == null then ""
    elif $id == "description" or $id == "comments" then ""
    elif type == "object" and .type == "doc" then rich_value | field_clean
    else display_value | field_clean
    end;

def parse_labels:
  if type == "object" then .
  elif type == "string" then
    split(",")
    | map(select(length > 0) | split(":")
        | select(length >= 2 and .[0] != "" and (.[1:] | join(":")) != "")
        | {key: .[0], value: (.[1:] | join(":"))})
    | from_entries
  else {}
  end;

def field_label($id; $labels):
  ($labels | parse_labels) as $custom
  | ($custom[$id] // field_names[$id] // $id);
