# Dependency checks shared by setup and the interactive installer. No config is
# sourced and no credentials or raw TWG diagnostics are printed.
# shellcheck disable=SC2034,SC2329
REQUIRED_TWG=1.2.6
TWG_INSTALL_GUIDE=https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/

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
  for dependency in fzf jq less; do
    if command -v "$dependency" >/dev/null 2>&1; then
      printf 'OK   %s is on PATH\n' "$dependency"
    else
      printf 'FAIL %s is required and missing from the PATH used by Herdr\n' "$dependency"
      dependency_failures=$((dependency_failures + 1))
    fi
  done
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
