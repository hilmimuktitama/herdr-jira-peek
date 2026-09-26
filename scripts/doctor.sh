#!/bin/sh
# shellcheck disable=SC1007,SC2012,SC2015,SC2016,SC2086,SC2329 # Read-only diagnostics use intentional shell idioms and trap callbacks.
# Read-only installation and configuration checks for Peek for Jira.
# shellcheck source=scripts/dependencies.sh
set -u
umask 077
. "$(dirname "$0")/dependencies.sh"
# shellcheck source=scripts/jira-rest.sh
. "$(dirname "$0")/jira-rest.sh"
# shellcheck source=scripts/preferences.sh
. "$(dirname "$0")/preferences.sh"

plugin_id=${HERDR_PLUGIN_ID:-jira-peek}
config_dir=${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}
config_file=$config_dir/config.sh
state=${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}
cache=$state/cache
required_twg=$REQUIRED_TWG
twg_bin=${TWG_BIN_PATH:-twg}
curl_bin=${CURL_BIN_PATH:-curl}
REST_CURL=$curl_bin
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
  JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' JIRA_BACKEND='' JIRA_NETRC_FILE='' JIRA_CLOUD_ID='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
  PICKER_LAYOUT=bottom SOURCE_HIGHLIGHT=off
  PICKER_FIELDS='status,summary'
  PREVIEW_FIELDS='status,assignee,updated,description,comments'
  READER_FIELDS='status,assignee,updated,link,description,comments'
  FIELD_LABELS=''
  TEXT_STYLE=bold
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
      JIRA_BACKEND=*)
        decode_config_value "${config_line#JIRA_BACKEND=}" || return 1
        JIRA_BACKEND=$config_value
        ;;
      JIRA_NETRC_FILE=*)
        decode_config_value "${config_line#JIRA_NETRC_FILE=}" || return 1
        JIRA_NETRC_FILE=$config_value
        ;;
      JIRA_CLOUD_ID=*)
        decode_config_value "${config_line#JIRA_CLOUD_ID=}" || return 1
        JIRA_CLOUD_ID=$config_value
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
      PICKER_LAYOUT=*)
        decode_config_value "${config_line#PICKER_LAYOUT=}" || return 1
        PICKER_LAYOUT=$config_value
        ;;
      SOURCE_HIGHLIGHT=*)
        decode_config_value "${config_line#SOURCE_HIGHLIGHT=}" || return 1
        SOURCE_HIGHLIGHT=$config_value
        ;;
      KEY_RE=*)
        decode_config_value "${config_line#KEY_RE=}" || return 1
        KEY_RE=$config_value
        ;;
      PICKER_FIELDS=*)
        decode_config_value "${config_line#PICKER_FIELDS=}" || return 1
        PICKER_FIELDS=$config_value
        ;;
      PREVIEW_FIELDS=*)
        decode_config_value "${config_line#PREVIEW_FIELDS=}" || return 1
        PREVIEW_FIELDS=$config_value
        ;;
      READER_FIELDS=*)
        decode_config_value "${config_line#READER_FIELDS=}" || return 1
        READER_FIELDS=$config_value
        ;;
      FIELD_LABELS=*)
        decode_config_value "${config_line#FIELD_LABELS=}" || return 1
        FIELD_LABELS=$config_value
        ;;
      COLOR_THEME=*)
        decode_config_value "${config_line#COLOR_THEME=}" || return 1
        case "$config_value" in
          terminal|ocean|warm|mono) : ;;
          *) return 1 ;;
        esac
        ;;
      TEXT_STYLE=*)
        decode_config_value "${config_line#TEXT_STYLE=}" || return 1
        TEXT_STYLE=$config_value
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
    JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' JIRA_BACKEND='' JIRA_NETRC_FILE='' JIRA_CLOUD_ID='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
  fi
else
  fail "config is missing at $config_file; run the setup action"
  JIRA_BASE='' JIRA_SITE='' JIRA_PROJECTS='' JIRA_BACKEND='' JIRA_NETRC_FILE='' JIRA_CLOUD_ID='' CACHE_TTL_MIN='' MAX_CANDIDATES='' KEY_RE=''
fi

JIRA_BASE=${JIRA_BASE:-}
JIRA_SITE=${JIRA_SITE:-}
JIRA_BACKEND=${JIRA_BACKEND:-twg}
JIRA_NETRC_FILE=${JIRA_NETRC_FILE:-}
JIRA_CLOUD_ID=${JIRA_CLOUD_ID:-}
JIRA_PROJECTS=${JIRA_PROJECTS:-}
CACHE_TTL_MIN=${CACHE_TTL_MIN:-}
MAX_CANDIDATES=${MAX_CANDIDATES:-}
KEY_RE=${KEY_RE:-}
PICKER_LAYOUT=${PICKER_LAYOUT-bottom}
PICKER_FIELDS=${PICKER_FIELDS-'status,summary'}
PREVIEW_FIELDS=${PREVIEW_FIELDS-'status,assignee,updated,description,comments'}
READER_FIELDS=${READER_FIELDS-'status,assignee,updated,link,description,comments'}
FIELD_LABELS=${FIELD_LABELS-}
TEXT_STYLE=${TEXT_STYLE-bold}

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

case "$JIRA_BACKEND" in
  twg|rest) ok "JIRA_BACKEND is valid ($JIRA_BACKEND)" ;;
  *) fail 'JIRA_BACKEND must be twg or rest' ;;
esac

if [ "$JIRA_BACKEND" = rest ]; then
  if [ -n "$JIRA_SITE" ]; then warn 'JIRA_SITE is ignored by the REST backend'; fi
  case "$JIRA_NETRC_FILE" in
    /*) ;;
    *) fail 'JIRA_NETRC_FILE must be an absolute path to a private netrc file' ;;
  esac
  if [ -n "$JIRA_NETRC_FILE" ]; then
    if [ -L "$JIRA_NETRC_FILE" ] || [ ! -f "$JIRA_NETRC_FILE" ]; then
      fail 'JIRA_NETRC_FILE is missing or is not a regular private file'
    elif rest_validate_netrc; then
      ok 'JIRA_NETRC_FILE uses private permissions'
    else
      fail 'JIRA_NETRC_FILE must use owner-only permissions (mode 400 or 600)'
    fi
  else
    fail 'JIRA_NETRC_FILE is required for the REST backend'
  fi
  if [ -n "$JIRA_CLOUD_ID" ]; then
    case "$JIRA_CLOUD_ID" in *[!A-Za-z0-9_-]*) fail 'JIRA_CLOUD_ID contains unsafe characters' ;; *) ok 'JIRA_CLOUD_ID is configured' ;; esac
  fi
fi

if [ "$JIRA_BACKEND" = twg ]; then
  case "$JIRA_SITE" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-]*)
      fail 'JIRA_SITE is missing or contains unsafe characters (use an Atlassian site prefix or cloud ID)' ;;
    *) ok 'JIRA_SITE is configured without exposing auth data' ;;
  esac
fi
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

case "$PICKER_LAYOUT" in
  top|bottom) ok "PICKER_LAYOUT is valid ($PICKER_LAYOUT)" ;;
  *) fail 'PICKER_LAYOUT must be top or bottom' ;;
esac
case "$SOURCE_HIGHLIGHT" in
  off|auto) ok "SOURCE_HIGHLIGHT is valid ($SOURCE_HIGHLIGHT)" ;;
  *) fail 'SOURCE_HIGHLIGHT must be off or auto' ;;
esac
if preferences_validate_field_list picker "$PICKER_FIELDS"; then
  ok "PICKER_FIELDS is valid (${PICKER_FIELDS:-key only})"
else
  fail 'PICKER_FIELDS contains an unsupported, duplicate, or malformed field'
fi
if preferences_validate_field_list preview "$PREVIEW_FIELDS"; then
  ok "PREVIEW_FIELDS is valid (${PREVIEW_FIELDS:-title only})"
else
  fail 'PREVIEW_FIELDS contains an unsupported, duplicate, or malformed field'
fi
if preferences_validate_field_list reader "$READER_FIELDS"; then
  ok "READER_FIELDS is valid (${READER_FIELDS:-title only})"
else
  fail 'READER_FIELDS contains an unsupported, duplicate, or malformed field'
fi
if preferences_validate_labels "$FIELD_LABELS"; then
  ok 'FIELD_LABELS is valid'
else
  fail 'FIELD_LABELS must be comma-separated field:label pairs'
fi
if preferences_validate_text_style "$TEXT_STYLE"; then
  ok "TEXT_STYLE is valid ($TEXT_STYLE)"
else
  fail 'TEXT_STYLE must be plain or bold'
fi
rest_config_failures=$failures

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
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail 'SHA-256 tooling is required; install sha256sum or shasum'
fi
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
if command -v "$curl_bin" >/dev/null 2>&1; then
  ok 'curl is available for progressive picker updates'
elif [ "$JIRA_BACKEND" = rest ]; then
  fail 'curl is required for the REST backend'
else
  warn 'curl is optional; metadata loads in one batch before the picker starts'
fi

twg_tmp=$(mktemp "${TMPDIR:-/tmp}/peek-for-jira-doctor.XXXXXX" 2>/dev/null || true)
rest_probe_status=
rest_probe_stderr=
cleanup() {
  [ -z "$twg_tmp" ] || rm -f "$twg_tmp"
  [ -z "$rest_probe_status" ] || rm -f "$rest_probe_status"
  [ -z "$rest_probe_stderr" ] || rm -f "$rest_probe_stderr"
}
trap cleanup 0 1 2 15
twg_available=1
if [ "$JIRA_BACKEND" = rest ]; then
  twg_available=0
  if [ "$rest_config_failures" -eq 0 ] && rest_validate_auth && [ -n "$twg_tmp" ]; then
    rest_probe_url=$(rest_origin)/rest/api/3/myself
    rest_probe_status=$twg_tmp.status
    rest_probe_stderr=$twg_tmp.stderr
    if rest_get "$rest_probe_url" "$twg_tmp" "$rest_probe_status" "$rest_probe_stderr" \
      && [ "$(sed -n '1p' "$rest_probe_status")" = 200 ] \
      && jq -s -e 'length == 1 and (.[0] | type) == "object" and (.[0].accountId | type) == "string" and (.[0].accountId | length) > 0' "$twg_tmp" >/dev/null 2>&1; then
      ok 'REST Jira authentication/connectivity check passed'
    else
      fail 'REST Jira authentication/connectivity check failed; verify JIRA_BASE, JIRA_CLOUD_ID, netrc permissions, and network access'
    fi
  else
    warn 'REST connectivity probe skipped until curl and a readable private netrc file are configured'
  fi
fi
if [ "$JIRA_BACKEND" = twg ] && ! command -v "$twg_bin" >/dev/null 2>&1; then
  if [ "$twg_bin" = twg ] && [ -n "${HOME:-}" ] \
    && [ -x "$HOME/.local/bin/twg" ]; then
    twg_bin=$HOME/.local/bin/twg
    fail 'TWG was found at ~/.local/bin/twg but is missing from the PATH used by Herdr; add ~/.local/bin to PATH and restart Herdr from the updated shell'
  else
    twg_available=0
    fail "TWG CLI is missing; install the official Atlassian TWG CLI (>= $required_twg), ensure it is on PATH, then run \`twg setup\`"
  fi
fi
if [ "$JIRA_BACKEND" = twg ] && [ "$twg_available" -eq 1 ]; then
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
    if "$twg_bin" --mode user --site "$JIRA_SITE" --output json whoami >"$twg_tmp" 2>/dev/null \
      && jq -s -e 'length == 1 and ((.[0].data.user // .[0].data // .[0]).accountId | type == "string" and length > 0)' "$twg_tmp" >/dev/null 2>&1; then
      ok 'TWG local account identity is available for cache isolation'
    else
      fail 'TWG local account identity is unavailable; verify twg setup'
      twg_auth_ok=0
    fi
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
