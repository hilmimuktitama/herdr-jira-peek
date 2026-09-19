# Dependency checks shared by setup and the interactive installer. No config is
# sourced and no credentials or raw TWG diagnostics are printed.
# shellcheck disable=SC2034,SC2329
REQUIRED_TWG=1.2.6
TWG_INSTALL_GUIDE=https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/

# Read only the backend selector from the declarative config.  This deliberately
# does not source config.sh: setup and diagnostics must never execute user data.
configured_backend() {
  backend_config_file=${1:-}
  backend_value=twg
  [ -f "$backend_config_file" ] || { printf '%s\n' "$backend_value"; return 0; }
  while IFS= read -r backend_line || [ -n "$backend_line" ]; do
    backend_line=$(printf '%s\n' "$backend_line" | sed 's/^[[:space:]]*//')
    case "$backend_line" in
      JIRA_BACKEND=*)
        backend_raw=${backend_line#JIRA_BACKEND=}
        backend_raw=$(printf '%s\n' "$backend_raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$backend_raw" in
          \"*\") backend_value=${backend_raw#\"}; backend_value=${backend_value%\"} ;;
          \'*\') backend_value=${backend_raw#\'}; backend_value=${backend_value%\'} ;;
          *) backend_value=$backend_raw ;;
        esac
        ;;
    esac
  done < "$backend_config_file"
  printf '%s\n' "$backend_value"
}

twg_version_supported() {
  dependency_version=$("$1" --version 2>/dev/null) || return 1
  printf '%s\n' "$dependency_version" | awk -v minimum="$REQUIRED_TWG" '
    BEGIN { split(minimum, r, ".") }
    match($0, /[0-9]+\.[0-9]+\.[0-9]+/) {
      split(substr($0, RSTART, RLENGTH), v, ".")
      supported = v[1] > r[1] || (v[1] == r[1] && (v[2] > r[2] || (v[2] == r[2] && v[3] >= r[3])))
      found = 1
      exit
    }
    END { exit !(found && supported) }
  '
}

check_dependencies() {
  dependency_failures=0
  dependency_config_file=${HERDR_PLUGIN_CONFIG_FILE:-${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-jira-peek}}/config.sh}
  dependency_backend=${HERDR_PLUGIN_DEPENDENCY_BACKEND:-$(configured_backend "$dependency_config_file")}
  case "$dependency_backend" in
    twg|rest) ;;
    *) printf 'FAIL JIRA_BACKEND must be twg or rest\n'; return 1 ;;
  esac
  dependency_list='fzf jq less'
  [ "$dependency_backend" = rest ] && dependency_list="$dependency_list curl"
  for dependency in $dependency_list; do
    dependency_executable=$dependency
    if [ "$dependency" = curl ]; then dependency_executable=${CURL_BIN_PATH:-curl}; fi
    if command -v "$dependency_executable" >/dev/null 2>&1; then
      printf 'OK   %s is on PATH\n' "$dependency"
    else
      printf 'FAIL %s is required and missing from the PATH used by Herdr\n' "$dependency"
      dependency_failures=$((dependency_failures + 1))
    fi
  done
  [ "$dependency_backend" = rest ] && { [ "$dependency_failures" -eq 0 ]; return "$dependency_failures"; }
  dependency_twg=${TWG_BIN_PATH:-twg}
  if ! command -v "$dependency_twg" >/dev/null 2>&1; then
    if [ "$dependency_twg" = twg ] && [ -n "${HOME:-}" ] && [ -x "$HOME/.local/bin/twg" ]; then
      printf '%s\n' 'FAIL TWG exists at ~/.local/bin/twg; add ~/.local/bin to the PATH used by Herdr and restart Herdr from the updated shell'
    else
      printf 'FAIL TWG CLI >= %s is required on PATH; install from %s\n' "$REQUIRED_TWG" "$TWG_INSTALL_GUIDE"
    fi
    dependency_failures=$((dependency_failures + 1))
  elif ! twg_version_supported "$dependency_twg"; then
    printf 'FAIL TWG version is unsupported or unreadable; install TWG CLI >= %s\n' "$REQUIRED_TWG"
    dependency_failures=$((dependency_failures + 1))
  elif "$dependency_twg" doctor -o json >/dev/null 2>&1; then
    printf '%s\n' 'OK   TWG version and authentication/connectivity checks passed'
  else
    printf '%s\n' 'FAIL TWG authentication/connectivity check failed; run twg setup yourself in a terminal if not authenticated, or check your network and retry'
    dependency_failures=$((dependency_failures + 1))
  fi
  [ "$dependency_failures" -eq 0 ]
}
