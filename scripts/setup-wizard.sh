#!/bin/sh
# Interactive, secret-free setup. A candidate is validated before activation.
set -eu
umask 077
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
config_dir=${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}
config_file=$config_dir/config.sh
template=$root/config.example.sh
[ -f "$template" ] || { printf '%s\n' 'Setup wizard: template is missing.' >&2; exit 1; }
case "$config_dir" in ''|/|.) exit 1 ;; esac
[ ! -L "$config_dir" ] && [ ! -L "$config_file" ] || exit 1
[ ! -e "$config_file" ] || [ -f "$config_file" ] || exit 1
mkdir -p "$config_dir"; chmod 700 "$config_dir"
candidate_dir=$(mktemp -d "$config_dir/.setup-candidate.XXXXXX")
candidate=$candidate_dir/config.sh
cleanup() { rm -rf "$candidate_dir"; }
trap 'cleanup; exit 1' 1 2 15
trap cleanup 0
existing=0
if [ -f "$config_file" ]; then
  existing=1
  cp "$config_file" "$candidate_dir/original"
  cp "$config_file" "$candidate"
else
  cp "$template" "$candidate"
fi
mkdir "$candidate_dir/state" "$candidate_dir/state/cache"
ask() { label=$1; current=$2; printf '%s [%s]: ' "$label" "$current" >&2; IFS= read -r answer || exit 1; [ -n "$answer" ] || answer=$current; [ "$answer" != - ] || answer=; printf '%s' "$answer"; }
backend=$(ask 'Backend (twg/rest)' "$(sed -n "s/^JIRA_BACKEND=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
[ -n "$backend" ] || backend=twg
case "$backend" in twg|rest) ;; *) printf '%s\n' 'Backend must be twg or rest.' >&2; exit 1 ;; esac
base=$(ask 'Jira base URL' "$(sed -n "s/^JIRA_BASE=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
projects=$(ask 'Project allowlist (ABC|DEF)' "$(sed -n "s/^JIRA_PROJECTS=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
if [ "$backend" = rest ]; then
  netrc=$(ask 'Absolute private netrc path' "$(sed -n "s/^JIRA_NETRC_FILE=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
  cloud=$(ask 'Optional Jira cloud ID (- clears)' "$(sed -n "s/^JIRA_CLOUD_ID=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
  printf '\n%s\n' "JIRA_BACKEND='$backend'" "JIRA_BASE='$base'" "JIRA_PROJECTS='$projects'" "JIRA_NETRC_FILE='$netrc'" "JIRA_CLOUD_ID='$cloud'" >> "$candidate"
else
  site=$(ask 'Atlassian site prefix/cloud ID' "$(sed -n "s/^JIRA_SITE=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$candidate" | tail -n 1 || true)")
  printf '\n%s\n' "JIRA_BACKEND='twg'" "JIRA_BASE='$base'" "JIRA_SITE='$site'" "JIRA_PROJECTS='$projects'" >> "$candidate"
fi
chmod 600 "$candidate"
# Detect credentials edited while the read-only validation request is pending.
# shellcheck source=scripts/connection.sh
. "$root/scripts/connection.sh"
credential_before=
if [ "$backend" = rest ]; then
  [ -f "$netrc" ] && [ ! -L "$netrc" ] || { printf '%s\n' 'Setup cancelled: private netrc file is missing.' >&2; exit 1; }
  credential_before=$(connection_hash < "$netrc") || exit 1
fi
if HERDR_PLUGIN_CONFIG_DIR="$candidate_dir" HERDR_PLUGIN_STATE_DIR="$candidate_dir/state" sh "$root/scripts/doctor.sh"; then
  if [ "$backend" = rest ] && { [ ! -f "$netrc" ] || [ -L "$netrc" ] || [ "$(connection_hash < "$netrc")" != "$credential_before" ]; }; then
    printf '%s\n' 'Setup cancelled: credentials changed during validation; rerun setup.' >&2
    exit 1
  fi
  if [ -L "$config_file" ] || { [ "$existing" -eq 1 ] && ! cmp -s "$candidate_dir/original" "$config_file"; } \
    || { [ "$existing" -eq 0 ] && [ -e "$config_file" ]; }; then
    printf '%s\n' 'Setup cancelled: config changed during validation; rerun setup.' >&2
    exit 1
  fi
  mv "$candidate" "$config_file"
  printf '%s\n' 'Setup complete. The validated connection is active.'
  printf '%s\n' 'Choose fields with Customize Peek for Jira.'
else
  rm -f "$candidate_dir/config.sh"; rmdir "$candidate_dir" 2>/dev/null || true
  printf '%s\n' 'Setup cancelled: validation failed; the previous config was preserved.' >&2
  printf 'For missing tools, open Install Peek for Jira dependencies and choose %s. Fix the reported authentication settings, then rerun setup.\n' "$backend" >&2
  exit 1
fi
