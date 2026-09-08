# Shared helpers. Sourced, not executed.
# shellcheck disable=SC2329,SC2034 # Cleanup is trap-indirect; sourced functions expose caller variables.
umask 077

HERDR="${HERDR_BIN_PATH:-herdr}"
TWG="${TWG_BIN_PATH:-twg}"
STATE="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$STATE}"
CACHE="$STATE/cache"

die() {
  printf 'jira-peek: %s\n' "$*" >&2
  exit 1
}

require_fzf() {
  command -v fzf >/dev/null 2>&1 || die 'fzf is required; install it with brew install fzf (macOS) or your Linux package manager, and make sure it is on the PATH used by Herdr. Then rerun the doctor action.'
}

require_twg() {
  command -v "$TWG" >/dev/null 2>&1 || die 'TWG CLI is required; run the setup action for dependency installation instructions, then complete twg setup yourself in a terminal.'
}

# Public defaults. Authentication belongs to TWG, not this plugin config.
JIRA_BASE=
JIRA_SITE=
JIRA_PROJECTS=
CACHE_TTL_MIN=10
MAX_CANDIDATES=20
KEY_RE=

# Config is a deliberately small declarative assignment file. Parse the six
# public settings as data instead of executing config.sh as shell code.
decode_config_value() {
  config_raw=$(printf '%s\n' "${1:-}" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$config_raw" in
    \'*\')
      config_value=${config_raw#\'}
      config_value=${config_value%\'}
      ;;
    \"*\")
      config_value=${config_raw#\"}
      config_value=${config_value%\"}
      ;;
    *\'*|*\"*) return 1 ;;
    *) config_value=$config_raw ;;
  esac
}

load_config() {
  config_file=$CONFIG_DIR/config.sh
  case "$CONFIG_DIR" in
    ''|/|.) die 'refusing unsafe plugin config directory path' ;;
  esac
  [ ! -L "$CONFIG_DIR" ] || die 'plugin config directory must not be a symlink'
  [ ! -L "$config_file" ] || die 'config.sh must not be a symlink'
  [ -f "$config_file" ] || return 0

  while IFS= read -r config_line || [ -n "$config_line" ]; do
    config_line=$(printf '%s\n' "$config_line" | sed 's/^[[:space:]]*//')
    case "$config_line" in
      ''|\#*) continue ;;
      JIRA_BASE=*)
        decode_config_value "${config_line#JIRA_BASE=}" || die 'invalid JIRA_BASE assignment in config.sh'
        JIRA_BASE=$config_value
        ;;
      JIRA_SITE=*)
        decode_config_value "${config_line#JIRA_SITE=}" || die 'invalid JIRA_SITE assignment in config.sh'
        JIRA_SITE=$config_value
        ;;
      JIRA_PROJECTS=*)
        decode_config_value "${config_line#JIRA_PROJECTS=}" || die 'invalid JIRA_PROJECTS assignment in config.sh'
        JIRA_PROJECTS=$config_value
        ;;
      CACHE_TTL_MIN=*)
        decode_config_value "${config_line#CACHE_TTL_MIN=}" || die 'invalid CACHE_TTL_MIN assignment in config.sh'
        CACHE_TTL_MIN=$config_value
        ;;
      MAX_CANDIDATES=*)
        decode_config_value "${config_line#MAX_CANDIDATES=}" || die 'invalid MAX_CANDIDATES assignment in config.sh'
        MAX_CANDIDATES=$config_value
        ;;
      KEY_RE=*)
        decode_config_value "${config_line#KEY_RE=}" || die 'invalid KEY_RE assignment in config.sh'
        KEY_RE=$config_value
        ;;
      *) die 'config.sh may contain only Peek for Jira setting assignments' ;;
    esac
  done < "$config_file"
}

load_config

JIRA_BASE=${JIRA_BASE:-}
while [ "${JIRA_BASE%/}" != "$JIRA_BASE" ]; do
  JIRA_BASE=${JIRA_BASE%/}
done

[ -n "${JIRA_BASE:-}" ] || die 'JIRA_BASE is required in config.sh'
case "$JIRA_BASE" in
  *[[:space:]]*) die 'JIRA_BASE must not contain whitespace' ;;
esac
printf '%s\n' "$JIRA_BASE" | grep -Eq '^https://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(:[0-9]+)?$' \
  || die 'JIRA_BASE must be a bare HTTPS origin without credentials, path, query, or fragment'

[ -n "${JIRA_SITE:-}" ] || die 'JIRA_SITE is required in config.sh'
case "$JIRA_SITE" in
  *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-]*)
    die 'JIRA_SITE must be an Atlassian site prefix or bare cloud ID'
    ;;
esac

[ -n "${JIRA_PROJECTS:-}" ] || die 'JIRA_PROJECTS must not be empty'
printf '%s\n' "$JIRA_PROJECTS" \
  | grep -Eq '^[A-Z][A-Z0-9_]*(\|[A-Z][A-Z0-9_]*)*$' \
  || die 'JIRA_PROJECTS must be an explicit allowlist such as ABC|DEF'
case "${CACHE_TTL_MIN:-}" in
  ''|*[!0-9]*) die 'CACHE_TTL_MIN must be a non-negative integer' ;;
esac
case "${MAX_CANDIDATES:-}" in
  ''|*[!0-9]*) die 'MAX_CANDIDATES must be a positive integer' ;;
esac
[ "$MAX_CANDIDATES" -gt 0 ] || die 'MAX_CANDIDATES must be greater than zero'
[ "$MAX_CANDIDATES" -le 100 ] || die 'MAX_CANDIDATES must not exceed 100'
# Check configured regular expressions without making a non-match an error.
regex_status=0
printf '\n' | grep -Eq "^(${JIRA_PROJECTS})-[0-9]+$" >/dev/null 2>&1 \
  || regex_status=$?
[ "$regex_status" -ne 2 ] || die 'JIRA_PROJECTS is not a valid regular expression'

if [ -z "${KEY_RE:-}" ]; then
  KEY_RE="(${JIRA_PROJECTS})-[0-9]+"
fi
regex_status=0
printf '\n' | grep -oE "$KEY_RE" >/dev/null 2>&1 || regex_status=$?
[ "$regex_status" -ne 2 ] || die 'KEY_RE is not a valid regular expression'

ensure_private_dir() {
  private_dir=${1:-}
  private_label=${2:-directory}
  case "$private_dir" in
    ''|/|.) die "refusing unsafe $private_label path" ;;
  esac
  [ ! -L "$private_dir" ] || die "$private_label must not be a symlink"
  if [ -e "$private_dir" ] && [ ! -d "$private_dir" ]; then
    die "$private_label must be a directory"
  fi
  mkdir -p "$private_dir" || die "could not create $private_label"
  chmod 700 "$private_dir" || die "could not protect $private_label"
}

ensure_private_dir "$STATE" 'plugin state directory'
ensure_private_dir "$CACHE" 'issue cache directory'

# Fetch temporaries include their creating process ID. A later invocation may
# safely remove a direct regular file only when that owner process is gone;
# active concurrent fetches are left untouched. This also recovers from SIGKILL,
# where no shell trap can run.
cleanup_abandoned_temps() {
  for stale_temp in "$@"; do
    [ -f "$stale_temp" ] && [ ! -L "$stale_temp" ] || continue
    stale_name=${stale_temp##*/}
    stale_stem=${stale_name%.*}
    stale_owner=${stale_stem##*.}
    case "$stale_owner" in
      ''|0|*[!0-9]*) continue ;;
    esac
    if ! kill -0 "$stale_owner" 2>/dev/null; then
      rm -f "$stale_temp" || die 'could not remove an abandoned temporary file'
    fi
  done
}
cleanup_abandoned_temps \
  "$STATE"/.twg-json.*.* \
  "$STATE"/.twg-stderr.*.* \
  "$STATE"/.twg-normalized.*.* \
  "$STATE"/.twg-error.*.* \
  "$STATE"/.issue-*.*.*

# Purge on every invocation, not only when a particular key is requested. This
# also removes interrupted fetches and makes TTL=0 a true no-durable-cache mode.
purge_cache() {
  for cache_file in "$CACHE"/* "$CACHE"/.[!.]* "$CACHE"/..?*; do
    [ -f "$cache_file" ] && [ ! -L "$cache_file" ] || continue
    if [ "$CACHE_TTL_MIN" -eq 0 ] \
      || [ -n "$(find "$cache_file" ! -mmin -"$CACHE_TTL_MIN" -print 2>/dev/null)" ]; then
      rm -f "$cache_file" || die 'could not purge an issue cache file'
    fi
  done
}
purge_cache

# Cache ordering is global to STATE, not to a Herdr session.  Network work never
# holds this lock; it protects only generation reads and the final rename.
CACHE_GENERATION_DIR="$STATE/cache-generations"
ensure_private_dir "$CACHE_GENERATION_DIR" 'cache generation directory'
cache_generation_path() { printf '%s/%s' "$CACHE_GENERATION_DIR" "$1"; }
cache_generation_read() {
  cache_generation_file=$(cache_generation_path "$1")
  [ ! -L "$cache_generation_file" ] || return 1
  if [ ! -e "$cache_generation_file" ]; then printf '0'; return 0; fi
  [ -f "$cache_generation_file" ] || return 1
  cache_generation_value=$(sed -n '1p' "$cache_generation_file" 2>/dev/null || true)
  case "$cache_generation_value" in ''|*[!0-9]*) return 1;; esac
  [ "$(printf '%s\n' "$cache_generation_value" | wc -c | tr -d ' ')" = "$(wc -c < "$cache_generation_file" | tr -d ' ')" ] || return 1
  printf '%s' "$cache_generation_value"
}
cache_generation_increment_locked() {
  cache_generation_key=$1
  cache_generation_file=$(cache_generation_path "$cache_generation_key")
  cache_generation_value=$(cache_generation_read "$cache_generation_key") || return 1
  cache_generation_value=$((cache_generation_value + 1))
  cache_generation_tmp=$(mktemp "$CACHE_GENERATION_DIR/.$cache_generation_key.XXXXXX") || {
    return 1
  }
  printf '%s\n' "$cache_generation_value" > "$cache_generation_tmp" \
    && mv "$cache_generation_tmp" "$cache_generation_file"
  cache_generation_status=$?
  rm -f "$cache_generation_tmp"
  return "$cache_generation_status"
}
cache_generation_bump() {
  cache_generation_key=$1
  cache_publish_lock "$cache_generation_key" || return 1
  cache_generation_increment_locked "$cache_generation_key"; cache_generation_status=$?
  cache_publish_unlock
  return "$cache_generation_status"
}
cache_publish_lock() {
  cache_publish_key=$1
  cache_publish_lock_dir="$CACHE_GENERATION_DIR/.$cache_publish_key.lock"
  [ ! -L "$cache_publish_lock_dir" ] || return 1
  cache_publish_owner=$(mktemp "$CACHE_GENERATION_DIR/.owner.$$.XXXXXX") || return 1
  printf '%s\n' "$$" > "$cache_publish_owner" || { rm -f "$cache_publish_owner"; return 1; }
  cache_lock_wait=0
  while ! mkdir "$cache_publish_lock_dir" 2>/dev/null; do
    cache_lock_tokens="$cache_publish_lock_dir/.owner.*"
    cache_lock_token_count=0; cache_lock_token=
    for cache_lock_candidate in $cache_lock_tokens; do
      [ -f "$cache_lock_candidate" ] && [ ! -L "$cache_lock_candidate" ] || continue
      cache_lock_token_count=$((cache_lock_token_count + 1)); cache_lock_token=$cache_lock_candidate
    done
    if [ "$cache_lock_token_count" -eq 1 ]; then
      cache_lock_owner=${cache_lock_token##*/}; cache_lock_owner=${cache_lock_owner#.owner.}; cache_lock_owner=${cache_lock_owner%%.*}
      case "$cache_lock_owner" in ''|*[!0-9]*) ;; *)
        if ! kill -0 "$cache_lock_owner" 2>/dev/null; then
          rm "$cache_lock_token" && rmdir "$cache_publish_lock_dir" 2>/dev/null || true
        fi ;;
      esac
    fi
    cache_lock_wait=$((cache_lock_wait + 1))
    [ "$cache_lock_wait" -lt 1000 ] || { rm -f "$cache_publish_owner"; return 1; }
    sleep 0.01
  done
  mv "$cache_publish_owner" "$cache_publish_lock_dir/" || { rm -f "$cache_publish_owner"; rmdir "$cache_publish_lock_dir"; return 1; }
  cache_publish_owner="$cache_publish_lock_dir/${cache_publish_owner##*/}"
  CACHE_PUBLISH_LOCK_HELD=1
}
cache_publish_unlock() {
  [ "${CACHE_PUBLISH_LOCK_HELD:-0}" -eq 1 ] || return 0
  [ -f "$cache_publish_owner" ] && [ ! -L "$cache_publish_owner" ] || return 1
  rm "$cache_publish_owner" && rmdir "$cache_publish_lock_dir" || return 1
  CACHE_PUBLISH_LOCK_HELD=0
}
cache_invalidate() {
  cache_invalidate_key=$1
  cache_publish_lock "$cache_invalidate_key" || return 1
  cache_generation_increment_locked "$cache_invalidate_key" || { cache_publish_unlock; return 1; }
  rm -f "$CACHE/$cache_invalidate_key.json" || { cache_publish_unlock; return 1; }
  cache_publish_unlock
}

HANDOFF_STATE_DIR="$STATE"
if [ -n "${HERDR_SOCKET_PATH:-}" ]; then
  command -v cksum >/dev/null 2>&1 || die 'cksum is required for socket-scoped state'
  session_id=$(printf '%s' "$HERDR_SOCKET_PATH" | cksum | awk '{print $1}')
  case "$session_id" in
    ''|*[!0-9]*) die 'could not derive a safe Herdr session id' ;;
  esac
  HANDOFF_STATE_DIR="$STATE/session-$session_id"
  ensure_private_dir "$HANDOFF_STATE_DIR" 'session state directory'
fi

cleanup_abandoned_viewers() {
  for stale_viewer in "$@"; do
    [ -d "$stale_viewer" ] && [ ! -L "$stale_viewer" ] || continue
    stale_viewer_name=${stale_viewer##*/}
    stale_viewer_stem=${stale_viewer_name%.*}
    stale_viewer_owner=${stale_viewer_stem##*.}
    case "$stale_viewer_owner" in
      ''|0|*[!0-9]*) continue ;;
    esac
    if ! kill -0 "$stale_viewer_owner" 2>/dev/null; then
      rm -rf "$stale_viewer" || die 'could not remove abandoned viewer state'
    fi
  done
}
cleanup_abandoned_viewers "$HANDOFF_STATE_DIR"/.viewer.*.*

KEY_FILE="$HANDOFF_STATE_DIR/key"
CANDIDATES_FILE="${VIEWER_STATE_DIR:-$HANDOFF_STATE_DIR}/candidates"
# viewer-pane stores the pane ID and stable terminal ID as one atomic record.
VIEWER_PANE_FILE="$HANDOFF_STATE_DIR/viewer-pane"
LOCK_DIR="$HANDOFF_STATE_DIR/.lock"
LOCK_HELD=0

# Fetch diagnostics are private, session-scoped state. Each key has its own
# file, and writers use a same-directory temp file plus rename so concurrent
# fetches cannot expose a partial diagnostic.
FETCH_ERROR_DIR="$HANDOFF_STATE_DIR/fetch-errors"
ensure_private_dir "$FETCH_ERROR_DIR" 'fetch diagnostic state directory'
cleanup_abandoned_temps "$FETCH_ERROR_DIR"/.fetch-error-*.*.*
FETCH_ERROR_GENERIC='TWG request failed'
FETCH_ERROR_TWG='TWG is not authenticated or configured; run twg setup, then retry'
FETCH_ERROR_JIRA='Jira request failed'
FETCH_ERROR_MISSING='TWG CLI unavailable; install the official Atlassian TWG CLI, ensure it is on PATH, then run twg setup'
for fetch_error_parent in "$STATE" "$STATE"/session-*; do
  [ -e "$fetch_error_parent" ] || continue
  [ -d "$fetch_error_parent" ] && [ ! -L "$fetch_error_parent" ] \
    || die 'refusing symlinked or invalid session state directory'
  fetch_error_dir="$fetch_error_parent/fetch-errors"
  [ -e "$fetch_error_dir" ] || continue
  [ -d "$fetch_error_dir" ] && [ ! -L "$fetch_error_dir" ] \
    || die 'refusing symlinked or invalid fetch diagnostic directory'
  for fetch_error_file in "$fetch_error_dir"/fetch-error-*; do
    [ -f "$fetch_error_file" ] && [ ! -L "$fetch_error_file" ] || continue
    fetch_error_value=$(sed -n '1p' "$fetch_error_file" 2>/dev/null || true)
    fetch_error_bytes=$(wc -c < "$fetch_error_file" | tr -d ' ')
    fetch_error_valid=1
    case "$fetch_error_value" in
      "$FETCH_ERROR_GENERIC") fetch_error_expected=$(printf '%s\n' "$FETCH_ERROR_GENERIC" | wc -c | tr -d ' ') ;;
      "$FETCH_ERROR_TWG") fetch_error_expected=$(printf '%s\n' "$FETCH_ERROR_TWG" | wc -c | tr -d ' ') ;;
      "$FETCH_ERROR_JIRA") fetch_error_expected=$(printf '%s\n' "$FETCH_ERROR_JIRA" | wc -c | tr -d ' ') ;;
      "$FETCH_ERROR_MISSING") fetch_error_expected=$(printf '%s\n' "$FETCH_ERROR_MISSING" | wc -c | tr -d ' ') ;;
      *) fetch_error_valid=0 ;;
    esac
    [ "$fetch_error_bytes" = "${fetch_error_expected:-}" ] || fetch_error_valid=0
    if [ "$fetch_error_valid" -eq 1 ] \
      && ! LC_ALL=C printf '%s\n' "$fetch_error_value" | cmp -s - "$fetch_error_file"; then
      fetch_error_valid=0
    fi
    [ "$fetch_error_valid" -eq 1 ] || rm -f "$fetch_error_file" \
      || die 'could not remove obsolete fetch diagnostic'
  done
done
FETCHED_FILE=

fetch_error_path() {
  fetch_error_key=${1:-}
  validate_key "$fetch_error_key" || return 1
  printf '%s/fetch-error-%s' "$FETCH_ERROR_DIR" "$fetch_error_key"
}

clear_fetch_error() {
  fetch_error_file=$(fetch_error_path "${1:-}") || return 1
  rm -f "$fetch_error_file"
}

# Keep only the first line, remove terminal controls, redact credential-like
# values, and hide paths/URLs before returning a diagnostic for display.
sanitize_fetch_error_file() {
  fetch_error_source=${1:-}
  [ -r "$fetch_error_source" ] || return 1
  fetch_error_safe=$(LC_ALL=C awk '
    NR == 1 {
      original = $0
      if (tolower(original) ~ /(token|password|passwd|secret|credential|cookie|authorization|bearer|basic|api[ _-]*key)/)
        exit 1
      gsub(/\t/, " ")
      gsub(/[[:cntrl:]]/, "")
      gsub(/https?:\/\/[^[:space:]]*/, "[url]")
      gsub(/[Aa]uthorization[[:space:]]*:[[:space:]]*[^[:space:]]*([[:space:]]+[^[:space:]]*)?/, "[redacted]")
      gsub(/[Bb]earer[[:space:]]+[^[:space:]]*/, "[redacted]")
      gsub(/[Bb]asic[[:space:]]+[^[:space:]]*/, "[redacted]")
       gsub(/[[:alnum:]_-]*(token|Token|TOKEN|password|Password|PASSWORD|secret|Secret|credential|Credential|CREDENTIAL|api[_-]key|API[_-]KEY)[[:alnum:]_-]*[[:space:]]*[:=][[:space:]]*\"[^\"]*\"/, "[redacted]")
       gsub(/[[:alnum:]_-]*(token|Token|TOKEN|password|Password|PASSWORD|secret|Secret|SECRET|credential|Credential|CREDENTIAL|api[_-]key|API[_-]KEY)[[:alnum:]_-]*[[:space:]]*[:=][[:space:]]*[^[:space:]]*/, "[redacted]")
      gsub(/[^[:space:]]*\/[^[:space:]]*/, "[path]")
      gsub(/[[:alpha:]]:\\[^[:space:]]*/, "[path]")
      if (tolower($0) ~ /(token|password|passwd|secret|credential|cookie|authorization|bearer|basic|api[ _-]*key)/)
        exit 1
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      print substr($0, 1, 200)
      exit
    }
  ' "$fetch_error_source" 2>/dev/null || true)

  [ -n "$fetch_error_safe" ] || return 1
  printf '%s\n' "$fetch_error_safe" \
    | LC_ALL=C awk 'NR == 1 && $0 ~ /[^[:print:]]/ { exit 1 }
                   NR == 1 && $0 ~ /[^[:space:]]/ { exit 0 }
                   { exit 1 }' >/dev/null 2>&1 || return 1
  case "$fetch_error_safe" in
    */*|*\\*) return 1 ;;
  esac
  printf '%s' "$fetch_error_safe"
}

extract_fetch_json_error() {
  fetch_error_source=${1:-}
  [ -r "$fetch_error_source" ] || return 1
  jq -er -s '
    def message:
      if type == "string" then .
      elif type == "object" and (.message | type) == "string" then .message
      else empty
      end;
    if length != 1 or (.[0] | type) != "object" then empty
    else
      .[0]
      | [(.error | message),
         (.message | message),
         (.errors |
         if type == "array" then .[] | message
         elif type == "object" then message
         else empty
         end)]
        | map(select(type == "string" and length > 0))
        | .[0] // empty
    end
  ' "$fetch_error_source" 2>/dev/null
}

# Classify only clear client/auth setup failures. A Jira 401/403 or a project
# permission error remains a Jira request failure unless TWG explicitly says
# its own credentials/site configuration is missing.
is_twg_auth_error() {
  auth_source=$1
  auth_extra=${2:-}
  if [ -n "$auth_source" ] && grep -Eiq \
    '(twg[^[:cntrl:]]*(not[[:space:]]+authenticated|authentication[[:space:]]+(required|failed|not[[:space:]]+configured)|credentials?[[:space:]].*(missing|not[[:space:]]+configured)|setup|login)|run[^[:alnum:]]+twg[[:space:]]+(setup|login)|auth\.conf|no[[:space:]]+(default[[:space:]]+)?site|configure[[:space:]]+twg)' \
    "$auth_source" 2>/dev/null; then
    return 0
  fi
  [ -n "$auth_extra" ] && grep -Eiq \
    '(twg[^[:cntrl:]]*(not[[:space:]]+authenticated|authentication[[:space:]]+(required|failed|not[[:space:]]+configured)|credentials?[[:space:]].*(missing|not[[:space:]]+configured)|setup|login)|run[^[:alnum:]]+twg[[:space:]]+(setup|login)|auth\.conf|no[[:space:]]+(default[[:space:]]+)?site|configure[[:space:]]+twg)' \
    "$auth_extra" 2>/dev/null
}

save_fetch_error() {
  fetch_error_key=${1:-}
  fetch_error_message=${2:-}
  fetch_error_file=$(fetch_error_path "$fetch_error_key") || return 1
  fetch_error_tmp=$(mktemp "$FETCH_ERROR_DIR/.fetch-error-$fetch_error_key.$$.XXXXXX") || return 1
  if printf '%s\n' "$fetch_error_message" > "$fetch_error_tmp" \
    && mv "$fetch_error_tmp" "$fetch_error_file"; then
    return 0
  fi
  rm -f "$fetch_error_tmp"
  return 1
}

record_fetch_error() {
  fetch_error_key=${1:-}
  fetch_error_prefix=${2:-$FETCH_ERROR_GENERIC}
  fetch_error_source=${3:-}
  fetch_error_fallback_source=${4:-}
  fetch_error_message=$FETCH_ERROR_GENERIC
  case "$fetch_error_prefix" in
    "$FETCH_ERROR_GENERIC"|"$FETCH_ERROR_TWG"|"$FETCH_ERROR_JIRA"|"$FETCH_ERROR_MISSING") fetch_error_message=$fetch_error_prefix ;;
  esac
  save_fetch_error "$fetch_error_key" "$fetch_error_message"
}

fetch_error_detail() {
  fetch_error_file=$(fetch_error_path "${1:-}") || return 1
  [ -s "$fetch_error_file" ] || return 1
  fetch_error_detail=$(sed -n '1p' "$fetch_error_file" 2>/dev/null || true)
  case "$fetch_error_detail" in
    "$FETCH_ERROR_GENERIC"|"$FETCH_ERROR_TWG"|"$FETCH_ERROR_JIRA"|"$FETCH_ERROR_MISSING") printf '%s' "$fetch_error_detail" ;;
    *) printf '%s' "$FETCH_ERROR_GENERIC" ;;
  esac
}

# Validate the complete issue key before it is used in a path or command.
validate_key() {
  key=${1:-}
  [ -n "$key" ] || return 1
  case "$key" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*) return 1 ;;
  esac
  printf '%s\n' "$key" | grep -Eq "^(${JIRA_PROJECTS})-[0-9]+$"
}

cache_entry_valid() {
  cache_key=${1:-}
  validate_key "$cache_key" || return 1
  cache_file="$CACHE/$cache_key.json"
  [ -s "$cache_file" ] \
    && [ "$CACHE_TTL_MIN" -gt 0 ] \
    && [ -n "$(find "$cache_file" -mmin -"$CACHE_TTL_MIN" -print 2>/dev/null)" ] \
    && jq -s -e --arg requested_key "$cache_key" \
      'length == 1 and ((.[0] | type) == "object") and .[0].key == $requested_key' \
      "$cache_file" >/dev/null 2>&1
}

clear_cache() {
  clear_cache_key=${1:-}
  if [ -n "$clear_cache_key" ]; then
    validate_key "$clear_cache_key" || die 'invalid Jira issue key'
    cache_invalidate "$clear_cache_key" || return 1
    clear_fetch_error "$clear_cache_key" || true
    return 0
  fi
  # Remove only direct, regular cache files. Never traverse a nested directory
  # that may have been created by another version or by user error.
  for clear_cache_file in "$CACHE"/* "$CACHE"/.[!.]* "$CACHE"/..?*; do
    [ -f "$clear_cache_file" ] && [ ! -L "$clear_cache_file" ] || continue
    rm -f "$clear_cache_file" || return 1
  done
  for clear_error_file in "$FETCH_ERROR_DIR"/* "$FETCH_ERROR_DIR"/.[!.]* "$FETCH_ERROR_DIR"/..?*; do
    [ -f "$clear_error_file" ] && [ ! -L "$clear_error_file" ] || continue
    rm -f "$clear_error_file" || return 1
  done
}

fetch_cleanup() {
  fetch_cleanup_file=${1:-}
  [ "$CACHE_TTL_MIN" -eq 0 ] || return 0
  case "$fetch_cleanup_file" in
    "$STATE"/.issue-*) rm -f "$fetch_cleanup_file" ;;
  esac
}

# fetch() uses private same-filesystem temporaries before publishing a cache
# entry. POSIX shell functions do not have local variables, so top-level
# callers can use this helper from their signal/exit traps as well.
fetch_work_cleanup() {
  for fetch_work_file in "${raw:-}" "${stderr:-}" "${normalized:-}" "${json_error:-}"; do
    case "$fetch_work_file" in
      "$STATE"/.twg-json.*|"$STATE"/.twg-stderr.*|\
      "$STATE"/.twg-normalized.*|"$STATE"/.twg-error.*)
        rm -f "$fetch_work_file"
        ;;
    esac
  done
  cache_publish_unlock || true
}

fetch_failure() {
  fetch_failure_key=${1:-}
  fetch_failure_prefix=${2:-$FETCH_ERROR_GENERIC}
  fetch_failure_source=${3:-}
  fetch_failure_fallback_source=${4:-}
  record_fetch_error "$fetch_failure_key" "$fetch_failure_prefix" \
    "$fetch_failure_source" "$fetch_failure_fallback_source" || true
  if cache_entry_valid "$fetch_failure_key"; then
    if clear_fetch_error "$fetch_failure_key"; then
      FETCHED_FILE=$CACHE/$fetch_failure_key.json
      printf '%s' "$CACHE/$fetch_failure_key.json"
      return 0
    fi
  fi
  return 1
}

save_key() {
  key=${1:-}
  validate_key "$key" || die "invalid Jira issue key"
  key_tmp=$(mktemp "${KEY_FILE%/*}/.key.XXXXXX") || die 'could not save selected issue'
  if ! { printf '%s\n' "$key" > "$key_tmp" && mv "$key_tmp" "$KEY_FILE"; }; then
    rm -f "$key_tmp"
    die 'could not save selected issue'
  fi
}

lock_is_stale() {
  [ -d "$LOCK_DIR" ] || return 1
  lock_owner=$(sed -n '1p' "$LOCK_DIR/pid" 2>/dev/null || true)
  case "$lock_owner" in
    ''|0|*[!0-9]*)
      [ -n "$(find "$LOCK_DIR" -prune -mmin +0 -print 2>/dev/null)" ]
      return ;;
  esac
  kill -0 "$lock_owner" 2>/dev/null && return 1
  return 0
}

lock_release() {
  if [ "${LOCK_HELD:-0}" -eq 1 ]; then
    lock_owner=$(sed -n '1p' "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ "$lock_owner" = "$$" ]; then
      rm -f "$LOCK_DIR/pid"
      rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  LOCK_HELD=0
}

lock_acquire() {
  lock_wait=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if lock_is_stale; then
      rm -f "$LOCK_DIR/pid"
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    lock_wait=$((lock_wait + 1))
    [ "$lock_wait" -lt 65 ] || die 'could not acquire Peek for Jira state lock'
    sleep 1
  done
  if ! printf '%s\n' "$$" > "$LOCK_DIR/pid"; then
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    die 'could not initialize Peek for Jira state lock'
  fi
  LOCK_HELD=1
  trap 'lock_release' 0
  trap 'lock_release; exit 1' 1 2 15
}

issue_url() {
  key=${1:-}
  validate_key "$key" || return 1

  cached="$CACHE/$key.json"
  if [ -s "$cached" ] \
    && jq -e --arg requested_key "$key" \
      'type == "object" and .key == $requested_key' "$cached" >/dev/null 2>&1; then
    url=$(jq -r '.url // empty' "$cached" 2>/dev/null || true)
    url_key=$(key_from_url "$url" 2>/dev/null || true)
    if [ "$url_key" = "$key" ]; then
      safe_url=$(jq -r 'if (.url | type) == "string" then (.url | gsub("[\u0000-\u001f\u007f-\u009f]"; "")) else empty end' "$cached" 2>/dev/null || true)
      if [ -n "$safe_url" ]; then
        printf '%s' "$safe_url"
        return 0
      fi
    fi
  fi
  printf '%s/browse/%s' "$JIRA_BASE" "$key"
}

# Extract only from the configured browse path. Query strings and fragments are
# allowed, but a second path segment or a different host is not.
key_from_url() {
  url=${1:-}
  prefix="$JIRA_BASE/browse/"
  case "$url" in
    "$prefix"*) rest=${url#"$prefix"} ;;
    *) return 1 ;;
  esac

  case "$rest" in
    *\?*) rest=${rest%%\?*} ;;
  esac
  case "$rest" in
    *\#*) rest=${rest%%\#*} ;;
  esac
  key=$rest
  case "$key" in
    */*) return 1 ;;
  esac
  validate_key "$key" || return 1
  printf '%s\n' "$key"
}

open_url() {
  url=$1
  case "$(uname -s 2>/dev/null || printf 'unknown')" in
    Darwin)
      command -v open >/dev/null 2>&1 || die 'open is unavailable on macOS'
      open "$url"
      ;;
    Linux)
      command -v xdg-open >/dev/null 2>&1 || die 'xdg-open is unavailable on Linux'
      xdg-open "$url"
      ;;
    *)
      die 'browser opening is supported on macOS and Linux only'
      ;;
  esac
}

copy_text() {
  text=$1
  case "$(uname -s 2>/dev/null || printf 'unknown')" in
    Darwin)
      command -v pbcopy >/dev/null 2>&1 || die 'pbcopy is unavailable on macOS'
      printf '%s' "$text" | pbcopy
      ;;
    Linux)
      if command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$text" | wl-copy
      elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$text" | xclip -selection clipboard
      elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$text" | xsel --clipboard --input
      else
        die 'no Linux clipboard command found (install wl-copy, xclip, or xsel)'
      fi
      ;;
    *)
      die 'clipboard copying is supported on macOS and Linux only'
      ;;
  esac
}

invalidate_cache() {
  key=${1:-}
  validate_key "$key" || die 'invalid Jira issue key'
  cache_invalidate "$key" || die 'could not invalidate issue cache'
}

# Pane id of the pane the action was invoked from.
pane_id() {
  if [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s' "$HERDR_PANE_ID"
    return
  fi
  # CLI/link-click invocations carry it in the context JSON instead.
  printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" \
    | sed -n 's/.*"focused_pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Scan one pane without conflating a failed Herdr read with grep's no-match.
scan_source() (
  scan_pane_arg=${1:?}; scan_source_arg=${2:?}
  scan_dir=$(mktemp -d "$HANDOFF_STATE_DIR/.scan.$$.XXXXXX") || exit 2
  scan_cleanup() { rm -rf "$scan_dir"; }
  trap scan_cleanup 0
  trap 'scan_cleanup; trap - 0; exit 2' 1 2 15
  scan_status=0
  "$HERDR" pane read "$scan_pane_arg" --source "$scan_source_arg" >"$scan_dir/raw" 2>/dev/null || scan_status=$?
  [ "$scan_status" -eq 0 ] || exit 2
  grep -oE "$KEY_RE" "$scan_dir/raw" | while IFS= read -r scan_key; do
    validate_key "$scan_key" && printf '%s\n' "$scan_key"
  done | awk '{ a[n++]=$0 } END { for (i=n-1; i>=0; i--) if (!seen[a[i]]++) print a[i] }' >"$scan_dir/keys"
  cat "$scan_dir/keys"
  [ -s "$scan_dir/keys" ] && exit 0 || exit 1
)

scan_candidates() (
  scan_pane=${1:?}; scan_out=${2:?}
  scan_dir=$(mktemp -d "$HANDOFF_STATE_DIR/.scan-all.$$.XXXXXX") || exit 2
  scan_cleanup() { rm -rf "$scan_dir"; }
  trap scan_cleanup 0
  trap 'scan_cleanup; trap - 0; exit 2' 1 2 15
  scan_visible="$scan_dir/visible"; scan_recent="$scan_dir/recent"; scan_tmp="$scan_dir/candidates"
  scan_status=0; scan_source "$scan_pane" visible >"$scan_visible" || scan_status=$?
  [ "$scan_status" -lt 2 ] || exit 2
  recent_status=0; scan_source "$scan_pane" recent-unwrapped >"$scan_recent" || recent_status=$?
  [ "$recent_status" -lt 2 ] || exit 2
  if [ -s "$scan_visible" ] || [ -s "$scan_recent" ]; then
    { cat "$scan_visible"; cat "$scan_recent"; } \
      | awk -v max="$MAX_CANDIDATES" '!seen[$0]++ && count++ < max' >"$scan_tmp"
  else
    detection_file="$scan_dir/detection"
    detection_status=0; scan_source "$scan_pane" detection >"$detection_file" || detection_status=$?
    [ "$detection_status" -lt 2 ] || exit 2
    awk -v max="$MAX_CANDIDATES" '!seen[$0]++ && count++ < max' "$detection_file" >"$scan_tmp"
  fi
  if [ -s "$scan_tmp" ]; then cp "$scan_tmp" "$scan_out"; exit 0; else exit 1; fi
)

# IDs are passed to the Herdr CLI, so accept only a conservative identifier
# shape and reject values that could be interpreted as an option.
validate_pane_id() {
  pane=${1:-}
  [ -n "$pane" ] || return 1
  case "$pane" in
    -*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-]*)
      return 1
      ;;
  esac
}

validate_terminal_id() {
  validate_pane_id "${1:-}"
}

# The session lock protects the registry and open/toggle handoff. Source state
# is keyed by stable terminal identity, never by focus or a mutable pane ID.
select_source_state() {
  scope_terminal=${1:-}
  validate_terminal_id "$scope_terminal" || die 'invalid source terminal ID'
  ensure_private_dir "$HANDOFF_STATE_DIR/sources" 'source registry directory'
  SOURCE_STATE_DIR="$HANDOFF_STATE_DIR/sources/source-$scope_terminal"
  ensure_private_dir "$SOURCE_STATE_DIR" 'source state directory'
  KEY_FILE="$SOURCE_STATE_DIR/key"
  CANDIDATES_FILE="${VIEWER_STATE_DIR:-$SOURCE_STATE_DIR}/candidates"
  VIEWER_PANE_FILE="$SOURCE_STATE_DIR/viewer-pane"
}

pane_terminal() {
  validate_pane_id "${1:-}" || return 1
  pane_response=$("$HERDR" pane get "$1" 2>/dev/null) || return 1
  printf '%s\n' "$pane_response" | jq -er \
    '.result.pane.terminal_id | select(type == "string" and length > 0)'
}

# Old records cannot be assigned to a source reliably. Never close an old
# viewer from an unrelated pane or silently open a duplicate beside it.
check_legacy_viewer() {
  legacy_file="$HANDOFF_STATE_DIR/viewer-pane"
  [ -f "$legacy_file" ] && [ ! -L "$legacy_file" ] || return 0
  legacy_terminal=$(sed -n '2p' "$legacy_file")
  if validate_terminal_id "$legacy_terminal"; then
    legacy_status=0
    legacy_pane=$(resolve_terminal_pane "$legacy_terminal") || legacy_status=$?
    if [ "$legacy_status" -eq 0 ]; then
      if [ "$action_terminal" = "$legacy_terminal" ]; then
        "$HERDR" plugin pane close "$legacy_pane" || die 'could not close pre-upgrade Peek viewer'
        rm -f "$legacy_file"
        exit 0
      fi
      die 'close the pre-upgrade Peek viewer with Esc, then invoke Peek again'
    fi
    [ "$legacy_status" -eq 1 ] || die 'could not inspect pre-upgrade Peek viewer'
  fi
  rm -f "$legacy_file"
}

resolve_action_source() {
  source_pane=$(pane_id)
  validate_pane_id "$source_pane" || die 'no valid pane in context'
  action_terminal=$(pane_terminal "$source_pane") || die 'could not inspect source pane'
  validate_terminal_id "$action_terminal" || die 'Herdr returned no valid source terminal ID'
  source_terminal=$action_terminal
  ACTION_IS_VIEWER=0
  # Reverse lookup also works after the viewer moves to another pane/workspace.
  for source_record in "$HANDOFF_STATE_DIR"/sources/source-*/viewer-pane; do
    [ -f "$source_record" ] && [ ! -L "$source_record" ] || continue
    [ "$(wc -l < "$source_record" | tr -d ' ')" = 2 ] || continue
    [ "$(sed -n '2p' "$source_record")" = "$action_terminal" ] || continue
    source_owner=${source_record%/viewer-pane}
    source_owner=${source_owner##*/source-}
    validate_terminal_id "$source_owner" || continue
    source_terminal=$source_owner
    ACTION_IS_VIEWER=1
    break
  done
  select_source_state "$source_terminal"
}

clear_viewer_tracking() {
  rm -f "$VIEWER_PANE_FILE" \
    || die 'could not remove viewer pane tracking'
}

save_viewer_tracking() {
  viewer_pane=${1:-}
  terminal=${2:-}
  validate_terminal_id "$terminal" || die 'Herdr returned an invalid viewer terminal ID'
  validate_pane_id "$viewer_pane" || die 'Herdr returned an invalid viewer pane ID'
  pane_tmp=$(mktemp "$HANDOFF_STATE_DIR/.viewer-pane.XXXXXX") \
    || die 'could not create viewer pane tracking file'
  if printf '%s\n%s\n' "$viewer_pane" "$terminal" > "$pane_tmp" \
    && mv "$pane_tmp" "$VIEWER_PANE_FILE"; then
    return 0
  fi
  rm -f "$pane_tmp" "$VIEWER_PANE_FILE"
  die 'could not save viewer pane tracking'
}

resolve_terminal_pane() {
  resolve_terminal=${1:-}
  validate_terminal_id "$resolve_terminal" || return 2
  resolve_workspaces=$(mktemp "$HANDOFF_STATE_DIR/.viewer-workspaces.XXXXXX") \
    || return 2
  resolve_panes=$(mktemp "$HANDOFF_STATE_DIR/.viewer-panes.XXXXXX") || {
    rm -f "$resolve_workspaces"
    return 2
  }

  resolve_status=0
  "$HERDR" workspace list > "$resolve_workspaces" || resolve_status=$?
  if [ "$resolve_status" -ne 0 ]; then
    rm -f "$resolve_workspaces" "$resolve_panes"
    return 2
  fi
  resolve_workspace_ids=$(jq -r \
    'if (.result.workspaces | type) != "array"
     then error("unexpected Herdr workspace response")
     else .result.workspaces[] | .workspace_id
     end
     | select(type == "string" and length > 0)' \
    "$resolve_workspaces" 2>/dev/null) || {
    rm -f "$resolve_workspaces" "$resolve_panes"
    return 2
  }

  for resolve_workspace in $resolve_workspace_ids; do
    validate_pane_id "$resolve_workspace" || {
      rm -f "$resolve_workspaces" "$resolve_panes"
      return 2
    }
    resolve_status=0
    "$HERDR" pane list --workspace "$resolve_workspace" > "$resolve_panes" \
      || resolve_status=$?
    if [ "$resolve_status" -ne 0 ]; then
      rm -f "$resolve_workspaces" "$resolve_panes"
      return 2
    fi
    resolve_match=$(jq -r --arg terminal "$resolve_terminal" \
      'if (.result.panes | type) != "array"
       then error("unexpected Herdr pane response")
       else .result.panes[]
       end
       | select(type == "object" and .terminal_id == $terminal
         and (.pane_id | type) == "string" and (.pane_id | length) > 0)
       | .pane_id' "$resolve_panes" 2>/dev/null) || {
      rm -f "$resolve_workspaces" "$resolve_panes"
      return 2
    }
    if [ -n "$resolve_match" ]; then
      validate_pane_id "$resolve_match" || {
        rm -f "$resolve_workspaces" "$resolve_panes"
        return 2
      }
      rm -f "$resolve_workspaces" "$resolve_panes"
      printf '%s\n' "$resolve_match"
      return 0
    fi
  done
  rm -f "$resolve_workspaces" "$resolve_panes"
  return 1
}

close_viewer_pane() {
  pane=${1:-}
  validate_pane_id "$pane" || die 'invalid viewer pane ID'
  close_status=0
  "$HERDR" plugin pane close "$pane" || close_status=$?
  if [ "$close_status" -ne 0 ]; then
    # The pane may still be live; retain tracking so the next toggle retries it.
    die "could not close Jira viewer pane (Herdr exited $close_status)"
  fi
  clear_viewer_tracking
}

# Toggle only, before any candidate/key writes. Returns 0 when it closed a viewer.
toggle_viewer() {
  [ -s "$VIEWER_PANE_FILE" ] || return 1
  [ "$(wc -l < "$VIEWER_PANE_FILE" | tr -d ' ')" = 2 ] || { clear_viewer_tracking; return 1; }
  toggle_pane=$(sed -n '1p' "$VIEWER_PANE_FILE" 2>/dev/null || true)
  toggle_terminal=$(sed -n '2p' "$VIEWER_PANE_FILE" 2>/dev/null || true)
  validate_pane_id "$toggle_pane" || { clear_viewer_tracking; return 1; }
  if [ "$(pane_terminal "$toggle_pane" || true)" = "$toggle_terminal" ] \
    && validate_terminal_id "$toggle_terminal"; then
    close_viewer_pane "$toggle_pane"; return 0
  fi
  validate_terminal_id "$toggle_terminal" || { clear_viewer_tracking; return 1; }
  toggle_resolve_tmp=$(mktemp "$HANDOFF_STATE_DIR/.toggle-resolve.XXXXXX") || die 'could not create viewer pane resolution file'
  toggle_status=0; resolve_terminal_pane "$toggle_terminal" >"$toggle_resolve_tmp" || toggle_status=$?
  if [ "$toggle_status" -eq 0 ]; then
    toggle_moved=$(sed -n '1p' "$toggle_resolve_tmp")
    rm -f "$toggle_resolve_tmp"
    validate_pane_id "$toggle_moved" || die 'Herdr returned an invalid moved viewer pane ID'
    close_viewer_pane "$toggle_moved"; return 0
  fi
  rm -f "$toggle_resolve_tmp"
  [ "$toggle_status" -eq 1 ] || die 'could not resolve the moved Jira viewer pane'
  clear_viewer_tracking
  return 1
}

# Open a viewer in an adjacent right-side split.
show() {
  # resolve_action_source captured the action's identity before any toggle.
  # Resolve again if a layout operation moved the terminal during the scan.
  if [ "$(pane_terminal "$source_pane" || true)" != "$source_terminal" ]; then
    source_pane=$(resolve_terminal_pane "$source_terminal") || die 'source terminal is no longer available'
  fi
  save_key "$1"

  open_tmp=$(mktemp "$HANDOFF_STATE_DIR/.viewer-open.XXXXXX") \
    || die 'could not create viewer open response file'
  open_status=0
  candidate_env=$(while IFS= read -r candidate_key || [ -n "$candidate_key" ]; do
    validate_key "$candidate_key" && printf '%s\n' "$candidate_key"
  done < "$CANDIDATES_FILE" | awk -v max="$MAX_CANDIDATES" '!seen[$0]++ && n++ < max')
  "$HERDR" plugin pane open \
    --plugin "$HERDR_PLUGIN_ID" \
    --entrypoint viewer \
    --placement split \
    --target-pane "$source_pane" \
    --direction right \
    --env "HERDR_VIEWER_SOURCE_PANE=$source_pane" \
    --env "HERDR_VIEWER_SOURCE_TERMINAL=$source_terminal" \
    --env "HERDR_VIEWER_CANDIDATES=$candidate_env" \
    --focus > "$open_tmp" || open_status=$?
  if [ "$open_status" -ne 0 ]; then
    rm -f "$open_tmp"
    die "could not open Jira viewer pane (Herdr exited $open_status)"
  fi

  opened_pane=$(jq -er \
    '.result.plugin_pane.pane.pane_id | select(type == "string" and length > 0)' \
    "$open_tmp" 2>/dev/null || true)
  opened_terminal=$(jq -er \
    '.result.plugin_pane.pane.terminal_id | select(type == "string" and length > 0)' \
    "$open_tmp" 2>/dev/null || true)
  rm -f "$open_tmp"
  validate_pane_id "$opened_pane" \
    || die 'Herdr returned no valid viewer pane ID'
  if ! validate_terminal_id "$opened_terminal"; then
    "$HERDR" plugin pane close "$opened_pane" >/dev/null 2>&1 || true
    die 'Herdr returned no valid viewer terminal ID'
  fi
  save_viewer_tracking "$opened_pane" "$opened_terminal"
}

# Run one metadata-only request for the keys listed in a file. The key file is
# generated from validated issue keys, so expanding the function's positional
# arguments cannot introduce options or shell syntax.
run_twg_metadata_batch() {
  metadata_keys_file=${1:-}
  metadata_raw=${2:-}
  metadata_stderr=${3:-}
  [ -r "$metadata_keys_file" ] || return 1
  [ -n "$metadata_raw" ] && [ -n "$metadata_stderr" ] || return 1
  command -v "$TWG" >/dev/null 2>&1 || return 127

  set --
  while IFS= read -r metadata_key || [ -n "$metadata_key" ]; do
    validate_key "$metadata_key" || continue
    set -- "$@" "$metadata_key"
  done < "$metadata_keys_file"
  [ "$#" -gt 0 ] || return 1

  metadata_status=0
  "$TWG" --mode user --api-version v2 --site "$JIRA_SITE" --output json \
    jira workitem get "$@" --fields summary,status,assignee,updated \
    > "$metadata_raw" 2> "$metadata_stderr" || metadata_status=$?
  return "$metadata_status"
}

metadata_row() {
  metadata_source=${1:-}
  metadata_requested_key=${2:-}
  [ -r "$metadata_source" ] || return 1
  jq -r -s -e --arg requested_key "$metadata_requested_key" '
    def docs:
      if length != 1 then []
      elif (.[0] | type) == "array" then .[0]
      elif (.[0] | type) != "object" then []
      elif (.[0].data | type) == "array" then .[0].data
      elif (.[0].data | type) == "object" and (.[0].data.items | type) == "array" then
        [.[0].data.items[] | select(type == "object" and .ok == true and (.data | type) == "object") | .data]
      elif (.[0].data | type) == "object" then [.[0].data]
      else [.[0]]
      end;
    def text: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; " ");
    docs[]
    | select(type == "object" and .key == $requested_key)
    | [(.key | text),
       (if (.status | type) == "object" then (.status.name // "?") else (.status // "?") end | text),
       ((.summary // "") | text)]
    | @tsv
  ' "$metadata_source"
}

# fetch KEY -> prints path of canonical issue JSON, using the cache when fresh.
# TWG is deliberately invoked with direct JSON output so the plugin never has
# to trust an indirect path to a second response file.
fetch() {
  key=${1:-}
  validate_key "$key" || return 1
  fetch_generation=$(cache_generation_read "$key") || return 1
  if [ "$CACHE_TTL_MIN" -gt 0 ]; then
    out="$CACHE/$key.json"
  else
    # Created only after a successful request. Callers consume this file
    # immediately and remove it after use; keeping it outside CACHE means
    # TTL=0 never creates a durable issue cache entry.
    out=
  fi

  if [ "$CACHE_TTL_MIN" -gt 0 ] && cache_entry_valid "$key"; then
    if ! clear_fetch_error "$key"; then
      if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
        return 0
      fi
      return 1
    fi
    FETCHED_FILE=$out
    printf '%s' "$out"
    return 0
  fi

  if ! command -v "$TWG" >/dev/null 2>&1; then
    if fetch_failure "$key" 'TWG CLI unavailable; install the official Atlassian TWG CLI, ensure it is on PATH, then run twg setup'; then
      return 0
    fi
    return 1
  fi

  raw=$(mktemp "$STATE/.twg-json.$$.XXXXXX") || {
    if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
      return 0
    fi
    return 1
  }
  stderr=$(mktemp "$STATE/.twg-stderr.$$.XXXXXX") || {
    rm -f "$raw"
    if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
      return 0
    fi
    return 1
  }
  normalized=$(mktemp "$STATE/.twg-normalized.$$.XXXXXX") || {
    rm -f "$raw" "$stderr"
    if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
      return 0
    fi
    return 1
  }
  twg_status=0
  "$TWG" --mode user --api-version v2 --site "$JIRA_SITE" --output json \
    jira workitem get "$key" --comments > "$raw" 2> "$stderr" \
    || twg_status=$?
  if [ "$twg_status" -ne 0 ]; then
    json_error=$(mktemp "$STATE/.twg-error.$$.XXXXXX") || {
      if fetch_failure "$key" 'Jira request failed' '' "$stderr"; then
        rm -f "$raw" "$stderr" "$normalized"
        return 0
      fi
      rm -f "$raw" "$stderr" "$normalized"
      return 1
    }
    fetch_failure_result=1
    if extract_fetch_json_error "$raw" > "$json_error"; then
      if is_twg_auth_error "$stderr" "$json_error"; then
        fetch_failure "$key" 'TWG is not authenticated or configured; run twg setup, then retry' "$json_error" "$stderr" \
          && fetch_failure_result=0
      elif fetch_failure "$key" 'Jira request failed' "$json_error" "$stderr"; then
        fetch_failure_result=0
      fi
    else
      if is_twg_auth_error "$stderr"; then
        fetch_failure "$key" 'TWG is not authenticated or configured; run twg setup, then retry' '' "$stderr" \
          && fetch_failure_result=0
      elif fetch_failure "$key" 'Jira request failed' '' "$stderr"; then
        fetch_failure_result=0
      fi
    fi
    rm -f "$raw" "$stderr" "$normalized" "$json_error"
    return "$fetch_failure_result"
  fi

  # Direct JSON may be an issue object. Accept a single data wrapper, including
  # TWG's single-item data array, but never accept multiple documents/issues or
  # an output-files envelope.
  if ! jq -s -e --arg requested_key "$key" '
    if length != 1 or (.[0] | type) != "object" then
      error("unexpected JSON response")
    else
      .[0] as $doc
       | (if ($doc.data | type) == "array" then
            if ($doc.data | length) == 1 then $doc.data[0] else error("multiple issues") end
          elif ($doc.data | type) == "object" then $doc.data
          else $doc
          end) as $issue
      | if ($issue | type) == "object" and $issue.key == $requested_key
        then $issue
        else error("unexpected issue JSON")
        end
    end
  ' "$raw" > "$normalized" 2>/dev/null; then
    if fetch_failure "$key" 'Jira response was not valid issue JSON' '' "$stderr"; then
      rm -f "$raw" "$stderr" "$normalized"
      return 0
    fi
    rm -f "$raw" "$stderr" "$normalized"
    return 1
  fi

  cache_publish_lock "$key" || {
    rm -f "$raw" "$stderr" "$normalized"
    return 1
  }
  published_generation=$(cache_generation_read "$key") || {
    cache_publish_unlock || true
    rm -f "$raw" "$stderr" "$normalized"
    return 1
  }
  if [ "$published_generation" != "$fetch_generation" ]; then
    cache_publish_unlock || true
    rm -f "$raw" "$stderr" "$normalized"
    return 1
  fi
  if [ "$CACHE_TTL_MIN" -eq 0 ]; then
    out=$(mktemp "$STATE/.issue-$key.$$.XXXXXX") || {
      cache_publish_unlock
      rm -f "$raw" "$stderr" "$normalized"
      return 1
    }
  fi
  if ! mv "$normalized" "$out"; then
    cache_publish_unlock
    rm -f "$raw" "$stderr" "$normalized"
    if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
      return 0
    fi
    return 1
  fi
  if ! cache_publish_unlock; then
    rm -f "$raw" "$stderr"
    return 1
  fi
  rm -f "$raw" "$stderr"
  if ! clear_fetch_error "$key"; then
    if fetch_failure "$key" "$FETCH_ERROR_GENERIC"; then
      return 0
    fi
    return 1
  fi
  FETCHED_FILE=$out
  printf '%s' "$out"
  return 0
}

# Viewer helpers inherit their source identity; they must never infer it from
# the focused terminal, which may belong to a different agent by now.
if [ -n "${HERDR_VIEWER_SOURCE_TERMINAL:-}" ]; then
  select_source_state "$HERDR_VIEWER_SOURCE_TERMINAL"
fi
