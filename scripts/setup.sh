#!/bin/sh
# Preserve or install the public config template, then check prerequisites.
# shellcheck source=scripts/dependencies.sh
# shellcheck disable=SC2329 # Cleanup is invoked by traps.
set -eu
umask 077
. "$(dirname "$0")/dependencies.sh"

plugin_id=${HERDR_PLUGIN_ID:-jira-peek}
config_dir=${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}
config_file=$config_dir/config.sh
plugin_root=${HERDR_PLUGIN_ROOT:-}

case "$config_dir" in
  ''|/|.)
    printf '%s\n' 'Peek for Jira setup: refusing an unsafe config directory.' >&2
    exit 1
    ;;
esac
if [ -L "$config_dir" ]; then
  printf '%s\n' 'Peek for Jira setup: refusing a symlinked config directory.' >&2
  exit 1
fi

if [ -z "$plugin_root" ]; then
  printf '%s\n' "Peek for Jira setup: HERDR_PLUGIN_ROOT is unavailable." >&2
  printf '%s\n' 'Run this action from Herdr so it can identify the installed plugin files.' >&2
  exit 1
fi

template=$plugin_root/config.example.sh
[ -f "$template" ] || {
  printf '%s\n' "Peek for Jira setup: template not found under HERDR_PLUGIN_ROOT." >&2
  exit 1
}

# Treat a dangling symlink as an existing config too: setup must never follow
# an ambiguous target or overwrite a user's file.
if [ -L "$config_file" ] || { [ -e "$config_file" ] && [ ! -f "$config_file" ]; }; then
  printf '%s\n' "Peek for Jira setup: refusing an unsafe config file at $config_file" >&2
  exit 1
fi

if [ -f "$config_file" ]; then
  printf '%s\n' "Peek for Jira setup: preserving existing config at $config_file"
else
  mkdir -p "$config_dir" || {
    printf '%s\n' "Peek for Jira setup: could not create $config_dir" >&2
    exit 1
  }
  chmod 700 "$config_dir" || {
    printf '%s\n' "Peek for Jira setup: could not protect $config_dir" >&2
    exit 1
  }

  tmp_file=$(mktemp "$config_dir/.config.sh.XXXXXX") || {
    printf '%s\n' 'Peek for Jira setup: could not create a private temporary config.' >&2
    exit 1
  }
  cleanup() { rm -f "$tmp_file"; }
  trap cleanup 0 1 2 15

  if ! cp "$template" "$tmp_file" || ! chmod 600 "$tmp_file"; then
    printf '%s\n' "Peek for Jira setup: could not install $config_file" >&2
    exit 1
  fi
  if ! mv "$tmp_file" "$config_file"; then
    printf '%s\n' "Peek for Jira setup: could not install $config_file" >&2
    exit 1
  fi

  printf '%s\n' 'Peek for Jira setup: config template installed.'
fi

setup_status=0
if ! check_dependencies; then
  setup_status=1
  printf '%s\n' 'Setup is incomplete. Select Install Peek for Jira dependencies to review and approve missing tool installations.'
  printf '%s\n' 'If TWG is installed but unauthenticated, run twg setup yourself in a terminal; the plugin never starts OAuth.'
fi
printf '%s\n' 'Next steps:'
printf '1. Edit %s and set JIRA_BASE, JIRA_SITE, and your narrow JIRA_PROJECTS allowlist.\n' "$config_file"
printf '%s\n' '2. Resolve any dependency or authentication failures above, then rerun setup.'
printf '%s\n' "3. Check the configuration and Jira access: herdr plugin action invoke --plugin $plugin_id doctor"
printf '%s\n' '4. Add the prefix+i keybinding shown in README.md, then reload Herdr: herdr server reload-config'
exit "$setup_status"
