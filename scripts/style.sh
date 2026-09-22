# Terminal-native emphasis. Colors use the host terminal's ANSI palette.
# shellcheck disable=SC2034 # Values are consumed by rendering callers.
peek_style() {
  PEEK_COLOR=0; PEEK_STYLE=0
  PEEK_BOLD=; PEEK_RESET=; PEEK_DIM=; PEEK_GREEN=; PEEK_YELLOW=; PEEK_RED=
  [ -z "${NO_COLOR:-}" ] || return 0
  PEEK_COLOR=1
  PEEK_RESET=$(printf '\033[0m')
  PEEK_GREEN=$(printf '\033[32m')
  PEEK_YELLOW=$(printf '\033[33m')
  PEEK_RED=$(printf '\033[31m')
  if [ "${TEXT_STYLE:-bold}" = bold ]; then
    PEEK_STYLE=1
    PEEK_BOLD=$(printf '\033[1m')
    PEEK_DIM=$(printf '\033[2m')
  fi
}
