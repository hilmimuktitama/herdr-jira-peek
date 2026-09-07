#!/bin/sh
# Install external tools only after explicit approval in an interactive terminal.
# shellcheck source=scripts/dependencies.sh
# shellcheck disable=SC2329 # Cleanup is invoked by traps.
set -eu
umask 077
. "$(dirname "$0")/dependencies.sh"

if [ ! -t 0 ] || [ ! -t 1 ]; then
  printf '%s\n' 'Dependency installation needs an interactive terminal. Select Install Peek for Jira dependencies in Herdr, or run this script in a terminal.' >&2
  exit 1
fi

confirm_install() {
  printf '\n%s\nRun this installation? [y/N] ' "$1"
  IFS= read -r install_answer || return 1
  case "$install_answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

install_package() {
  package=$1
  if command -v brew >/dev/null 2>&1; then
    set -- brew install "$package"
  elif [ "$(uname -s)" = Linux ]; then
    if command -v apt-get >/dev/null 2>&1; then
      set -- apt-get install "$package"
    elif command -v dnf >/dev/null 2>&1; then
      set -- dnf install "$package"
    elif command -v pacman >/dev/null 2>&1; then
      set -- pacman -S "$package"
    else
      printf 'Install %s with your package manager, then rerun setup.\n' "$package"
      return
    fi
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null 2>&1 || { printf '%s\n' 'sudo is unavailable; install the package yourself.'; return; }
      set -- sudo "$@"
    fi
  else
    printf 'Install %s using your package manager, then rerun setup.\n' "$package"
    return
  fi
  if confirm_install "$*"; then
    "$@" || printf 'Installation of %s failed; review the package-manager output and retry.\n' "$package"
  fi
}

installer_file=
cleanup() { [ -z "$installer_file" ] || rm -f "$installer_file"; }
trap cleanup 0
trap 'exit 1' 1 2 15

printf '%s\n' 'Peek for Jira dependencies: fzf, jq, less, and TWG CLI.'
printf '%s\n' 'Each installation requires approval. TWG OAuth login remains a separate step.'
for dependency in fzf jq less; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    install_package "$dependency"
  fi
done

install_twg=${TWG_BIN_PATH:-twg}
if ! command -v "$install_twg" >/dev/null 2>&1 || ! twg_version_supported "$install_twg"; then
  if [ "$install_twg" != twg ]; then
    printf '%s\n' 'TWG_BIN_PATH is customized; update that installation yourself.'
  elif [ -n "${HOME:-}" ] && [ -x "$HOME/.local/bin/twg" ]; then
    printf '%s\n' 'TWG already exists at ~/.local/bin/twg. Add ~/.local/bin to the PATH used by Herdr; upgrade that installation if it is too old.'
  elif ! command -v curl >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
    printf 'The TWG installer requires curl and bash. Install TWG yourself: %s\n' "$TWG_INSTALL_GUIDE"
  elif confirm_install 'Download and run https://teamwork-graph.atlassian.com/cli/install with bash --skip-login --skip-skills. The Atlassian installer manages TWG files and may update your shell PATH; it will not log you in.'; then
    installer_file=$(mktemp "${TMPDIR:-/tmp}/jira-peek-twg-install.XXXXXX")
    if curl -fsSL --retry 2 https://teamwork-graph.atlassian.com/cli/install -o "$installer_file"; then
      bash "$installer_file" --skip-login --skip-skills || printf '%s\n' 'TWG installation failed; review the installer output and retry.'
    else
      printf '%s\n' 'Could not download the TWG installer. No installer was executed.'
    fi
  fi
fi

dependency_status=0
check_dependencies || dependency_status=1
printf '\n%s\n' 'If TWG was just installed, follow its PATH instructions, then run twg setup yourself to complete OAuth.'
printf '%s\n' 'Ensure Herdr sees the updated PATH, then rerun Set up Peek for Jira and Check Peek for Jira.'
printf '%s' 'Press Enter to close this installer. '
IFS= read -r install_answer || true
exit "$dependency_status"
