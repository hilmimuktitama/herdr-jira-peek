#!/bin/sh
# Install the public config template for Peek for Jira.
set -eu
umask 077

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
if [ -e "$config_file" ] || [ -L "$config_file" ]; then
  printf '%s\n' "Peek for Jira setup: refusing to overwrite $config_file" >&2
  printf '%s\n' 'No files were changed. Edit the existing config, then run the doctor action.' >&2
  exit 1
fi

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
printf '%s\n' 'Next steps (run these exactly, after editing the template values):'
printf '1. Edit %s and set JIRA_BASE, JIRA_SITE, and your narrow JIRA_PROJECTS allowlist.\n' "$config_file"
printf '%s\n' '2. Authenticate TWG with Atlassian OAuth once: twg setup'
printf '%s\n' '3. Install the required fzf executable: brew install fzf on macOS, or use your Linux package manager. It must be on the PATH used by Herdr.'
printf '%s\n' "4. Check the installation: herdr plugin action invoke --plugin $plugin_id doctor"
printf '%s\n' '5. Add the prefix+i keybinding shown in README.md, then reload Herdr: herdr server reload-config'
