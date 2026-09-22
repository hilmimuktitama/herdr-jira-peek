# Format a key plus ordered, tab-separated picker field values. The first
# column is always the fzf identity key; fields names and labels are supplied
# by the caller so the same formatter can render the picker and customization
# previews.
function clip(s,n) {
  if (length(s) <= n) return s
  if (s ~ /[^ -~]/) return s
  return substr(s,1,n-3) "..."
}
function builtin_label(id) {
  if (id == "status") return "Status"
  if (id == "summary") return "Summary"
  if (id == "assignee") return "Assignee"
  if (id == "reporter") return "Reporter"
  if (id == "priority") return "Priority"
  if (id == "issuetype") return "Type"
  if (id == "project") return "Project"
  if (id == "created") return "Created"
  if (id == "updated") return "Updated"
  if (id == "duedate") return "Due date"
  if (id == "resolution") return "Resolution"
  if (id == "labels") return "Labels"
  if (id == "components") return "Components"
  if (id == "fixVersions") return "Fix versions"
  if (id == "versions") return "Affects versions"
  if (id == "parent") return "Parent"
  return id
}
function label(id, parts, n, i, colon) {
  n=split(labels, parts, ",")
  for (i=1; i<=n; i++) {
    colon=index(parts[i], ":")
    if (colon > 1 && substr(parts[i], 1, colon-1) == id) return substr(parts[i], colon+1)
  }
  return builtin_label(id)
}
function has_alias(id, parts, n, i, colon) {
  n=split(labels, parts, ",")
  for (i=1; i<=n; i++) {
    colon=index(parts[i], ":")
    if (colon > 1 && substr(parts[i], 1, colon-1) == id) return 1
  }
  return 0
}
function compact_builtin(id) {
  return id == "status" || id == "assignee" || id == "priority" || id == "summary"
}
function status_color(s, l) {
  l=tolower(s)
  if (l ~ /^(done|closed|resolved)/) return green
  if (l ~ /(progress|review|qa|testing)/) return yellow
  if (l ~ /(block|hold)/) return red
  return dim
}
function safe_value(id, value) {
  if (value != "") return value
  if (id == "status") return "?"
  return ""
}
BEGIN {
  field_count=0
  if (fields != "") field_count=split(fields, names, ",")
}
{
  k=$1
  # Keep the historical compact status/summary row for the defaults.
  if (field_count == 2 && names[1] == "status" && names[2] == "summary" \
      && !has_alias("status") && !has_alias("summary")) {
    s=clip(safe_value("status", $2),18); l=tolower(s); c=status_color(s,l)
    printf "%s\t%-*s  %s%-18s%s  %s%s\n",k,kw,k,c,s,reset,$3,reset
    next
  }
  if (field_count == 0) {
    printf "%s\t%-*s\n", k, kw, k
    next
  }
  text=""
  for (i=1; i<=field_count; i++) {
    id=names[i]; value=safe_value(id, $(i+1)); if (value == "") value="—"; if (id != "summary") value=clip(value, 42)
    explicit=has_alias(id)
    if (id == "status") {
      l=tolower(value); c=status_color(value,l)
      segment=(explicit ? label(id) ": " : "") c value reset
    } else {
      if (explicit || !compact_builtin(id)) segment=label(id) ": " value
      else segment=value
    }
    if (text != "") text=text " · "
    text=text segment
  }
  printf "%s\t%-*s  %s\n",k,kw,k,text
}
