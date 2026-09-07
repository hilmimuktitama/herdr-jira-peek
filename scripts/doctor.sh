#!/bin/sh
# shellcheck disable=SC1007,SC2012,SC2015,SC2016,SC2086,SC2329 # Read-only diagnostics use intentional shell idioms and trap callbacks.
# Read-only installation and configuration checks for Peek for Jira.
# shellcheck source=scripts/dependencies.sh
set -u
umask 077
. "$(dirname "$0")/dependencies.sh"

plugin_id=${HERDR_PLUGIN_ID:-jira-peek}
config_dir=${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}
config_file=$config_dir/config.sh
state=${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}
cache=$state/cache
required_twg=$REQUIRED_TWG
twg_bin=${TWG_BIN_PATH:-twg}
failures=0
warnings=0

ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }

printf '%s\n' "Peek for Jira doctor ($plugin_id)"

decode_config_value() {
  config_raw=$(printf '%s\n' "${1:-}" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$config_raw" in
    \'*\') config_value=${config_raw#\'}; config_value=${config_value%\'} ;;
    \"*\") config_value=${config_raw#\"}; config_value=${config_value%\"} ;;
    *\'*|*\"*) return 1 ;;
    *) config_value=$config_raw ;;
  esac
}

read_config() {
  JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
  while IFS= read -r config_line || [ -n "$config_line" ]; do
    config_line=$(printf '%s\n' "$config_line" | sed 's/^[[:space:]]*//')
    case "$config_line" in
      ''|\#*) continue ;;
      JIRA_BASE=*)
        decode_config_value "${config_line#JIRA_BASE=}" || return 1
        JIRA_BASE=$config_value
        ;;
      JIRA_SITE=*)
        decode_config_value "${config_line#JIRA_SITE=}" || return 1
        JIRA_SITE=$config_value
        ;;
      JIRA_PROJECTS=*)
        decode_config_value "${config_line#JIRA_PROJECTS=}" || return 1
        JIRA_PROJECTS=$config_value
        ;;
      CACHE_TTL_MIN=*)
        decode_config_value "${config_line#CACHE_TTL_MIN=}" || return 1
        CACHE_TTL_MIN=$config_value
        ;;
      MAX_CANDIDATES=*)
        decode_config_value "${config_line#MAX_CANDIDATES=}" || return 1
        MAX_CANDIDATES=$config_value
        ;;
      KEY_RE=*)
        decode_config_value "${config_line#KEY_RE=}" || return 1
        KEY_RE=$config_value
        ;;
      *) return 1 ;;
    esac
  done < "$config_file"
}

if [ -f "$config_file" ] && [ ! -L "$config_file" ] \
  && [ ! -L "$config_dir" ]; then
  if read_config; then
    ok 'config.sh contains only supported setting assignments'
  else
    fail 'config.sh must contain only supported quoted setting assignments'
    JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
  fi
else
  fail "config is missing at $config_file; run the setup action"
  JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
fi

JIRA_BASE=${JIRA_BASE:-}
JIRA_SITE=${JIRA_SITE:-}
JIRA_PROJECTS=${JIRA_PROJECTS:-}
CACHE_TTL_MIN=${CACHE_TTL_MIN:-}
MAX_CANDIDATES=${MAX_CANDIDATES:-}
KEY_RE=${KEY_RE:-}

case "$JIRA_BASE" in
  *[[:space:]]*) fail 'JIRA_BASE contains whitespace' ;;
  https://[[]*[]]|https://[A-Za-z0-9.-]*|https://[A-Za-z0-9.-]*:* )
    # The exact host/port grammar is checked below with grep; this case only
    # keeps the diagnostic useful on shells with differing glob behavior.
    if printf '%s\n' "$JIRA_BASE" | grep -Eq '^https://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(:[0-9]+)?$'; then
      ok 'JIRA_BASE is a bare HTTPS origin'
    else
      fail 'JIRA_BASE must be a bare HTTPS origin without credentials, path, query, or fragment'
    fi
    ;;
  *) fail 'JIRA_BASE must be a bare HTTPS origin without credentials, path, query, or fragment' ;;
esac

case "$JIRA_SITE" in
  ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-]*)
    fail 'JIRA_SITE is missing or contains unsafe characters (use an Atlassian site prefix or cloud ID)' ;;
  *) ok 'JIRA_SITE is configured without exposing auth data' ;;
esac

if [ -n "$JIRA_PROJECTS" ] && printf '%s\n' "$JIRA_PROJECTS" | grep -Eq '^[A-Z][A-Z0-9_]*(\|[A-Z][A-Z0-9_]*)+$'; then
  ok 'JIRA_PROJECTS is an explicit narrow allowlist'
elif [ -n "$JIRA_PROJECTS" ] && printf '%s\n' "$JIRA_PROJECTS" | grep -Eq '^[A-Z][A-Z0-9_]*$'; then
  ok 'JIRA_PROJECTS contains one explicit project'
else
  fail 'JIRA_PROJECTS must be an explicit allowlist such as ABC|DEF (broad wildcards are not accepted)'
fi

regex_status=0
if [ -n "$JIRA_PROJECTS" ]; then
  printf '\n' | grep -Eq "^(${JIRA_PROJECTS})-[0-9]+$" >/dev/null 2>&1 || regex_status=$?
  [ "$regex_status" -ne 2 ] && ok 'JIRA_PROJECTS is a valid issue-key expression' || fail 'JIRA_PROJECTS is not a valid regular expression'
fi

case "$CACHE_TTL_MIN" in
  ''|*[!0-9]*) fail 'CACHE_TTL_MIN must be a non-negative integer' ;;
  *) ok 'CACHE_TTL_MIN is valid' ;;
esac
case "$MAX_CANDIDATES" in
  ''|*[!0-9]*) fail 'MAX_CANDIDATES must be a positive integer (20 is recommended)' ;;
  0) fail 'MAX_CANDIDATES must be greater than zero' ;;
  *)
    if [ "$MAX_CANDIDATES" -le 100 ]; then
      ok 'MAX_CANDIDATES is valid'
    else
      fail 'MAX_CANDIDATES must not exceed 100'
    fi
    ;;
esac

check_dir_mode() {
  check_dir=$1
  check_label=$2
  if [ ! -e "$check_dir" ]; then
    warn "$check_label is not present yet ($check_dir)"
  elif [ -L "$check_dir" ] || [ ! -d "$check_dir" ]; then
    fail "$check_label is not a private directory"
  elif [ ! -r "$check_dir" ] || [ ! -w "$check_dir" ] || [ ! -x "$check_dir" ]; then
    fail "$check_label is not readable/writable/searchable by the current user"
  else
    mode=$(ls -ld "$check_dir" 2>/dev/null | awk 'NR == 1 { print $1 }')
    case "$mode" in
      drwx------*) ok "$check_label uses owner-only permissions" ;;
      *) fail "$check_label must use owner-only permissions (700)" ;;
    esac
  fi
}
check_dir_mode "$config_dir" 'config directory'
check_dir_mode "$state" 'plugin state directory'
check_dir_mode "$cache" 'issue cache directory'

for dependency in jq grep sed awk find mktemp mkdir chmod mv; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required dependency missing: $dependency"
done
if command -v less >/dev/null 2>&1; then
  ok 'a pager is available'
else
  fail 'no pager found; install less'
fi
if command -v fzf >/dev/null 2>&1; then
  ok 'fzf is available for the interactive picker'
else
  fail 'fzf is required; install it with brew install fzf (macOS) or your Linux package manager, and make sure it is on the PATH used by Herdr'
fi
if command -v curl >/dev/null 2>&1; then ok 'curl is available for progressive picker updates'; else warn 'curl is optional; metadata loads in one batch before the picker starts'; fi

twg_tmp=$(mktemp "${TMPDIR:-/tmp}/peek-for-jira-doctor.XXXXXX" 2>/dev/null || true)
cleanup() { [ -z "$twg_tmp" ] || rm -f "$twg_tmp"; }
trap cleanup 0 1 2 15
twg_available=1
if ! command -v "$twg_bin" >/dev/null 2>&1; then
  if [ "$twg_bin" = twg ] && [ -n "${HOME:-}" ] \
    && [ -x "$HOME/.local/bin/twg" ]; then
    twg_bin=$HOME/.local/bin/twg
    fail 'TWG was found at ~/.local/bin/twg but is missing from the PATH used by Herdr; add ~/.local/bin to PATH and restart Herdr from the updated shell'
  else
    twg_available=0
    fail "TWG CLI is missing; install the official Atlassian TWG CLI (>= $required_twg), ensure it is on PATH, then run \`twg setup\`"
  fi
fi
if [ "$twg_available" -eq 1 ]; then
  if twg_version_supported "$twg_bin"; then
    ok "TWG CLI meets minimum version $required_twg"
  else
    fail "TWG CLI is older than minimum $required_twg or its version could not be read"
  fi

  # Capture all TWG output. This check is intentionally read-only and never
  # invokes login/setup; no auth, URL, or issue content is printed.
  twg_auth_ok=0
  if [ -z "$twg_tmp" ]; then
    fail 'could not create a private temporary file for TWG diagnostics'
  elif "$twg_bin" doctor -o json >"$twg_tmp" 2>&1; then
    ok 'TWG reports a configured authenticated session'
    twg_auth_ok=1
  elif grep -Eiq '(timed?[ -]?out|network|connection|ECONN|ENOTFOUND|DNS)' "$twg_tmp" 2>/dev/null; then
    fail 'TWG could not complete its connectivity check; verify network access and retry'
  else
    fail 'TWG is not authenticated or not configured; run `twg setup` outside this plugin'
  fi

  # A site filter confirms that the configured site is passed to TWG without
  # displaying the response. A failed probe is actionable but never prints its
  # captured response, which could contain tenant data.
  if [ "$twg_auth_ok" -eq 1 ] && [ -n "$JIRA_SITE" ] && [ -n "$twg_tmp" ] \
    && "$twg_bin" --site "$JIRA_SITE" access \
      --product jira-software.ondemand --site-filter "$JIRA_SITE" \
      -o json >"$twg_tmp" 2>&1; then
    ok 'TWG can probe the configured Jira Cloud site'
  elif [ "$twg_auth_ok" -eq 1 ] && [ -n "$JIRA_SITE" ]; then
    fail 'TWG could not probe JIRA_SITE; verify the site prefix/cloud ID and OAuth access'
  elif [ -n "$JIRA_SITE" ]; then
    warn 'JIRA_SITE probe skipped until TWG authentication/connectivity passes'
  fi
fi

if [ "$failures" -eq 0 ]; then
  printf '%s\n' "Peek for Jira doctor: passed ($warnings warning(s))."
else
  printf '%s\n' "Peek for Jira doctor: $failures check(s) need attention ($warnings warning(s))." >&2
fi
exit "$failures"
