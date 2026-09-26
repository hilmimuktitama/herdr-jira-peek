# Peek for Jira configuration template.
# shellcheck disable=SC2034 # These assignments are exported data for the runtime.
# The setup action copies this file from $HERDR_PLUGIN_ROOT; it never copies
# from the caller's current working directory.
# Keep this file declarative: one supported NAME=value assignment per line.
# Quote string values. It is parsed as data and never executed as shell code.

# Backend is `twg` by default. Set `rest` to use Jira Cloud REST directly.
JIRA_BACKEND='twg'

# Jira Cloud browse origin, without a trailing slash. Required for both backends.
JIRA_BASE='https://your-site.atlassian.net'

# TWG's Atlassian site prefix (or bare cloud ID). Required for the TWG backend.
JIRA_SITE='your-site'

# REST credentials live in an external netrc file, never in this config.
# Use an absolute path to a mode-600 file containing the Jira API email/token.
JIRA_NETRC_FILE=''

# Optional Jira Cloud ID for the api.atlassian.com gateway. When empty, REST
# requests use JIRA_BASE as the machine host.
JIRA_CLOUD_ID=''

# Keep this allowlist narrow. Add projects explicitly (for example ABC|DEF).
JIRA_PROJECTS='ABC|DEF'

# Retention for lazily fetched full previews, in minutes. Use 0 for no durable
# issue cache; picker metadata is temporary either way.
CACHE_TTL_MIN=10

# Number of recent issues to preload metadata for (1–100).
# All detected keys remain searchable; older issues load when previewed.
MAX_CANDIDATES=20

# Picker reading direction: 'bottom' (default) places the newest issue and
# filter at the bottom, with preview above. 'top' keeps the original view.
# Reopen the Peek pane after changing this setting.
PICKER_LAYOUT='bottom'

# Native source-terminal highlight for the currently selected Jira key.
# Requires the patched Herdr build described in native/README.md.
# 'off' preserves current behavior; 'auto' enables it when supported.
# Reopen Peek after changing this setting.
SOURCE_HIGHLIGHT='off'

# Optional: override the scan expression instead of deriving it from JIRA_PROJECTS.
# Detected keys must still match JIRA_PROJECTS; this cannot expand the allowlist.
# KEY_RE='(ABC|DEF)-[0-9]+'

# Choose the ordered fields shown in the picker and issue views. The issue key
# is always retained as the selection identity. Empty values are allowed.
PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status,assignee,updated,description,comments'
READER_FIELDS='status,assignee,updated,link,description,comments'

# Optional human labels for standard or custom fields. Keep labels concise.
# FIELD_LABELS='customfield_10016:Points,duedate:Due'

# Uses the terminal's colors. Optional: remove heading emphasis and dim text.
# TEXT_STYLE='plain'
