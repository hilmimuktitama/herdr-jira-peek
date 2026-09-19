#!/bin/sh
# Isolated setup/installer regressions. Never use live TWG, package managers,
# installers, or credentials, including when testing the approval path.
# shellcheck disable=SC2016,SC2012
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-dependencies.XXXXXX")
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 15
expect_path=$(command -v expect || true)
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config" "$tmp/state"
printf '%s\n' "JIRA_BASE='https://jira.example.test'" "JIRA_SITE='jira-example'" "JIRA_PROJECTS='ABC'" 'CACHE_TTL_MIN=10' 'MAX_CANDIDATES=20' > "$tmp/config/config.sh"
chmod 600 "$tmp/config/config.sh"
for tool in env sh dirname sed awk mkdir chmod mktemp cp mv rm rmdir grep find wc tr cksum date cat uname id ls stat shasum whoami; do
  ln -s "$(command -v "$tool")" "$tmp/bin/$tool"
done
cat > "$tmp/ok" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/good-twg" <<'EOF'
#!/bin/sh
case " $* " in *' whoami '*) printf '%s\n' '{"accountId":"fictional-user"}'; exit 0 ;; esac
printf '%s\n' "$*" >> "$DEPS_LOG"
case "$1" in
  --version) printf 'twg version %s\n' "${TEST_TWG_VERSION:-1.2.6}"; exit "${TEST_VERSION_STATUS:-0}" ;;
  --site) exit 0 ;;
  doctor) printf '%s\n' 'SYNTHETIC_PRIVATE_DIAGNOSTIC'; exit "${TEST_AUTH_STATUS:-0}" ;;
  *) exit 99 ;;
esac
EOF
chmod 700 "$tmp/ok" "$tmp/good-twg"
for tool in fzf jq less; do cp "$tmp/ok" "$tmp/bin/$tool"; done
cp "$tmp/good-twg" "$tmp/bin/twg"
cat > "$tmp/bin/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$INSTALL_LOG"
cp "$DEPS_TMP/ok" "$DEPS_TMP/bin/$2"
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$INSTALL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; printf '%s\n' 'synthetic installer' > "$1"; break; fi
  shift
done
exit "${TEST_DOWNLOAD_STATUS:-0}"
EOF
cat > "$tmp/bin/bash" <<'EOF'
#!/bin/sh
printf 'bash %s\n' "$*" >> "$INSTALL_LOG"
[ "$2" = --skip-login ] && [ "$3" = --skip-skills ] || exit 99
cp "$DEPS_TMP/good-twg" "$DEPS_TMP/bin/twg"
EOF
cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/sh
printf 'herdr %s\n' "$*" >> "$INSTALL_LOG"
EOF
chmod 700 "$tmp/bin/brew" "$tmp/bin/curl" "$tmp/bin/bash" "$tmp/bin/herdr"
: > "$tmp/deps.log"
: > "$tmp/install.log"
deps_run() {
  env PATH="$tmp/bin" HOME="$tmp/home" DEPS_TMP="$tmp" DEPS_LOG="$tmp/deps.log" \
    INSTALL_LOG="$tmp/install.log" TWG_BIN_PATH=twg HERDR_BIN_PATH=herdr \
    HERDR_PLUGIN_ROOT="$ROOT" HERDR_PLUGIN_ID=jira-peek \
    HERDR_PLUGIN_CONFIG_DIR="$tmp/config" HERDR_PLUGIN_STATE_DIR="$tmp/state" "$@"
}
fail() { printf 'not ok - dependencies: %s\n' "$*" >&2; exit 1; }

deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1 || fail 'ready setup'
[ -f "$tmp/config/config.sh" ] || fail 'config missing'
case "$(ls -ld "$tmp/config/config.sh")" in -rw-------*) ;; *) fail 'config permissions' ;; esac
printf '%s\n' '# user settings must survive' >> "$tmp/config/config.sh"
cp "$tmp/config/config.sh" "$tmp/expected-config"
deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1 || fail 'setup rerun'
cmp "$tmp/config/config.sh" "$tmp/expected-config" || fail 'setup overwrote existing config'
for tool in fzf twg; do
  mv "$tmp/bin/$tool" "$tmp/saved-$tool"
  if deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail "missing $tool accepted"; fi
  grep -q 'Setup is incomplete' "$tmp/output" || fail 'incomplete setup not explained'
  mv "$tmp/saved-$tool" "$tmp/bin/$tool"
done
for version in 0.9.9 1.2.5 invalid; do
  if deps_run env TEST_TWG_VERSION="$version" sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'unsupported TWG accepted'; fi
done
for version in 1.2.6 1.12.0 2.0.0; do
  deps_run env TEST_TWG_VERSION="$version" sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1 || fail 'supported TWG rejected'
done
if deps_run env TEST_VERSION_STATUS=17 sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'failed version command accepted'; fi
if deps_run env TEST_AUTH_STATUS=17 sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'failed authentication accepted'; fi
grep -q 'authentication/connectivity check failed' "$tmp/output" || fail 'auth diagnostic'
if grep -q SYNTHETIC_PRIVATE_DIAGNOSTIC "$tmp/output"; then fail 'TWG output leaked'; fi
if grep -Eq '^(setup|login)' "$tmp/deps.log"; then fail 'OAuth was invoked'; fi
cmp "$tmp/config/config.sh" "$tmp/expected-config" || fail 'failed checks changed config'
mkdir -p "$tmp/home/.local/bin"
mv "$tmp/bin/twg" "$tmp/home/.local/bin/twg"
if deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'TWG outside PATH accepted'; fi
grep -q 'TWG exists at ~/.local/bin/twg' "$tmp/output" || fail 'TWG PATH repair guidance'
if deps_run sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then fail 'doctor accepts TWG outside PATH'; fi
grep -q 'FAIL TWG was found at ~/.local/bin/twg' "$tmp/output" || fail 'doctor PATH repair guidance'
mv "$tmp/home/.local/bin/twg" "$tmp/bin/twg"
rm "$tmp/config/config.sh"
ln -s "$tmp/nonexistent" "$tmp/config/config.sh"
if deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'symlink accepted'; fi
rm "$tmp/config/config.sh"
cp "$tmp/expected-config" "$tmp/config/config.sh"

if deps_run sh "$ROOT/scripts/install-dependencies.sh" </dev/null > "$tmp/output" 2>&1; then fail 'noninteractive install accepted'; fi
[ ! -s "$tmp/install.log" ] || fail 'noninteractive installer ran a command'
deps_run sh "$ROOT/scripts/install-dependencies-action.sh" || fail 'installer action'
grep -Fqx 'herdr plugin pane open --plugin jira-peek --entrypoint dependencies --placement split --focus' "$tmp/install.log" || fail 'installer action target'

deps_run sh "$ROOT/scripts/setup-action.sh" || fail 'setup action'
grep -Fqx 'herdr plugin pane open --plugin jira-peek --entrypoint setup-wizard --placement split --focus' "$tmp/install.log" || fail 'setup action target'

# Missing TWG fails before any pane command or TWG request, even with cached data.
mv "$tmp/bin/twg" "$tmp/saved-twg"
: > "$tmp/install.log"
for entrypoint in peek peek-url viewer; do
  if deps_run sh "$ROOT/scripts/$entrypoint.sh" > "$tmp/output" 2>&1; then fail 'missing TWG opened viewer'; fi
  grep -q 'TWG CLI is required' "$tmp/output" || fail 'missing TWG runtime diagnostic'
done
[ ! -s "$tmp/install.log" ] || fail 'missing TWG touched a pane'
mv "$tmp/saved-twg" "$tmp/bin/twg"

# REST mode is dependency-aware and never falls back to TWG. Keep this probe
# offline: a missing curl must fail setup and doctor without touching TWG.
cp "$tmp/expected-config" "$tmp/config/config.sh"
printf '%s\n' "JIRA_BACKEND='rest'" "JIRA_NETRC_FILE='$tmp/netrc'" >> "$tmp/config/config.sh"
printf '%s\n' 'machine jira.example.test login fictional password fictional' > "$tmp/netrc"
chmod 600 "$tmp/netrc"
mv "$tmp/bin/curl" "$tmp/saved-curl"
if deps_run sh "$ROOT/scripts/setup.sh" > "$tmp/output" 2>&1; then fail 'REST setup accepted missing curl'; fi
grep -q 'curl is required' "$tmp/output" || fail 'REST curl dependency diagnostic'
if deps_run env CURL_BIN_PATH=curl sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then fail 'REST doctor accepted missing curl'; fi
grep -q 'curl is required for the REST backend' "$tmp/output" || fail 'REST doctor curl diagnostic'
if grep -q 'TWG CLI' "$tmp/output"; then fail 'REST doctor checked TWG'; fi
mv "$tmp/saved-curl" "$tmp/bin/curl"
cp "$tmp/expected-config" "$tmp/config/config.sh"

cat > "$tmp/bin/rest-curl" <<'EOF'
#!/bin/sh
body=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; body=$1 ;;
    *) ;;
  esac
  shift
done
printf '%s\n' request >> "${REST_REQUEST_LOG:-/dev/null}"
if [ "${REST_MALFORMED:-0}" = 1 ]; then
  printf '%s\n' '<html>fictional</html>' > "$body"
  printf '%s' '200'
else
  printf '%s\n' '{"accountId":"fictional-account"}' > "$body"
fi
printf '%s' '200'
EOF
chmod 700 "$tmp/bin/rest-curl"
# JSON validation must use the real parser; the generic dependency stub only
# reports executable availability and cannot check an HTTP response.
real_jq=$(command -v jq)
mv "$tmp/bin/jq" "$tmp/bin/jq.fake"
ln -s "$real_jq" "$tmp/bin/jq"
printf '%s\n' "JIRA_BACKEND='rest'" "JIRA_NETRC_FILE='$tmp/netrc'" >> "$tmp/config/config.sh"
if deps_run env CURL_BIN_PATH=rest-curl sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then :; else fail 'REST doctor rejected valid offline response'; fi
grep -q 'REST Jira authentication/connectivity check passed' "$tmp/output" || fail 'REST success diagnostic'
if grep -q 'TWG CLI' "$tmp/output"; then fail 'REST doctor checked TWG after successful probe'; fi
chmod 400 "$tmp/netrc"
if deps_run env CURL_BIN_PATH=rest-curl sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then :; else fail 'REST doctor rejected mode 400 netrc'; fi
chmod 600 "$tmp/netrc"
cp "$tmp/expected-config" "$tmp/config/config.sh"
printf '%s\n' "JIRA_BACKEND='rest'" "JIRA_NETRC_FILE='$tmp/netrc'" "JIRA_CLOUD_ID='bad/id'" >> "$tmp/config/config.sh"
: > "$tmp/rest-requests"
if deps_run env CURL_BIN_PATH=rest-curl REST_REQUEST_LOG="$tmp/rest-requests" sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then fail 'invalid cloud ID accepted'; fi
[ ! -s "$tmp/rest-requests" ] || fail 'invalid cloud ID triggered REST request'
cp "$tmp/expected-config" "$tmp/config/config.sh"
printf '%s\n' "JIRA_BACKEND='rest'" "JIRA_NETRC_FILE='$tmp/netrc'" >> "$tmp/config/config.sh"
if deps_run env CURL_BIN_PATH=rest-curl REST_MALFORMED=1 sh "$ROOT/scripts/doctor.sh" > "$tmp/output" 2>&1; then fail 'malformed REST response accepted'; fi
rm "$tmp/bin/jq"
mv "$tmp/bin/jq.fake" "$tmp/bin/jq"
cp "$tmp/expected-config" "$tmp/config/config.sh"

if [ -n "$expect_path" ]; then
  cat > "$tmp/install.exp" <<'EOF'
set timeout 15
log_user 0
spawn sh $env(HERDR_PLUGIN_ROOT)/scripts/install-dependencies.sh
expect {
  -re {Backend tools to install.*: } { if {[info exists env(INSTALL_BACKEND)]} { send -- "$env(INSTALL_BACKEND)\r" } else { send -- "\r" }; exp_continue }
  -exact {Run this installation? [y/N]} { send -- "$env(INSTALL_REPLY)\r"; exp_continue }
  -exact {Press Enter to close this installer.} { send -- "\r"; exp_continue }
  eof {}
  timeout { exit 98 }
}
exit [lindex [wait] 3]
EOF
  rm "$tmp/bin/fzf" "$tmp/bin/twg"
  : > "$tmp/install.log"
  if deps_run env INSTALL_REPLY=n "$expect_path" "$tmp/install.exp"; then fail 'declined missing tools reported ready'; fi
  [ ! -s "$tmp/install.log" ] || fail 'declining ran an installer'
  deps_run env INSTALL_REPLY=y "$expect_path" "$tmp/install.exp" || fail 'approved fake installation'
  grep -q '^brew install fzf$' "$tmp/install.log" || fail 'fzf install not run'
  grep -q '^bash .* --skip-login --skip-skills$' "$tmp/install.log" || fail 'TWG login/skills not skipped'
  rm "$tmp/bin/twg"
  : > "$tmp/install.log"
  if deps_run env INSTALL_REPLY=y TEST_DOWNLOAD_STATUS=22 "$expect_path" "$tmp/install.exp"; then fail 'failed download reported ready'; fi
  if grep -q '^bash ' "$tmp/install.log"; then fail 'failed download executed'; fi
  : > "$tmp/install.log"; : > "$tmp/deps.log"
  deps_run env INSTALL_REPLY=y INSTALL_BACKEND=rest "$expect_path" "$tmp/install.exp" || fail 'REST tools choice while TWG remains active'
  [ ! -s "$tmp/install.log" ] && [ ! -s "$tmp/deps.log" ] || fail 'REST tools choice invoked TWG'
  [ ! -e "$tmp/bin/twg" ] || fail 'REST tools choice installed TWG'
  cmp "$tmp/expected-config" "$tmp/config/config.sh" || fail 'installer changed active connection'
else
  printf '%s\n' 'ok - dependencies: interactive approval checks skipped (expect unavailable)'
fi
printf '%s\n' 'ok - dependency setup, preservation, diagnostics, and installer approval'
