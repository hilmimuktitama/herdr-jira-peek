# Peek for Jira configuration template.
# shellcheck disable=SC2034 # These assignments are exported data for the runtime.
# The setup action copies this file from $HERDR_PLUGIN_ROOT; it never copies
# from the caller's current working directory.
# TWG owns Atlassian OAuth authentication; never put a token or credential here.
# Keep this file declarative: one supported quoted NAME=value assignment per
# line. It is parsed as data and is never executed as shell code.

# Jira Cloud browse origin, without a trailing slash. Required.
JIRA_BASE='https://your-site.atlassian.net'

# TWG's Atlassian site prefix (or bare cloud ID). Required for site checks.
JIRA_SITE='your-site'

# Keep this allowlist narrow. Add projects explicitly (for example ABC|DEF).
JIRA_PROJECTS='ABC|DEF'

# Retention for lazily fetched full previews, in minutes. Use 0 for no durable
# issue cache; picker metadata is temporary either way.
CACHE_TTL_MIN=10

# Maximum issue candidates handed from the focused pane to the picker.
MAX_CANDIDATES=20

# Optional: override the scan expression instead of deriving it from JIRA_PROJECTS.
# KEY_RE='(ABC|DEF)-[0-9]+'
