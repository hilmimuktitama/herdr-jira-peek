#!/bin/sh
set -eu
# shellcheck disable=SC2016 # Fake command scripts contain literal child variables.
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jira-peek-wizard.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 15
mkdir -p "$tmp/bin" "$tmp/state"; chmod 700 "$tmp" "$tmp/state"
cat > "$tmp/bin/twg" <<'EOF'
#!/bin/sh
case " $* " in *' whoami '*) printf '%s\n' '{"accountId":"fictional-user"}'; exit 0 ;; esac
case "$1" in --version) echo 'twg version 1.2.6';; doctor|access|--site) exit 0;; *) exit 1;; esac
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/sh
body=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; body=$1;; -w) shift;; esac
  shift
done
printf '%s\n' '{"accountId":"fictional-account"}' > "$body"
if [ -n "${WIZARD_GATE:-}" ]; then
  : > "$WIZARD_GATE.started"
  while [ ! -e "$WIZARD_GATE.release" ]; do sleep 0.02; done
fi
printf '%s' "${WIZARD_HTTP:-200}"
EOF
chmod 700 "$tmp/bin/twg" "$tmp/bin/curl"
printf '%s\n' "JIRA_BASE='https://jira.example.test'" "JIRA_SITE='fictional-site'" "JIRA_PROJECTS='ABC'" 'CACHE_TTL_MIN=10' 'MAX_CANDIDATES=20' "PICKER_LAYOUT='top'" > "$tmp/state/config.sh"
chmod 600 "$tmp/state/config.sh"
printf '%s\n' 'machine jira.example.test login fictional password fictional' > "$tmp/netrc"; chmod 600 "$tmp/netrc"
run_wizard() { env PATH="$tmp/bin:$PATH" HERDR_PLUGIN_CONFIG_DIR="${1:-$tmp/state}" HERDR_PLUGIN_STATE_DIR="$tmp/state" HERDR_PLUGIN_ROOT="$ROOT" TWG_BIN_PATH="$tmp/bin/twg" CURL_BIN_PATH="$tmp/bin/curl" sh "$ROOT/scripts/setup-wizard.sh"; }
printf '%s\n' rest https://jira.example.test ABC "$tmp/netrc" - | run_wizard >/dev/null 2>&1
grep -q "JIRA_BACKEND='rest'" "$tmp/state/config.sh"
printf '%s\n' twg https://jira.example.test ABC fictional-site | run_wizard >/dev/null 2>&1
grep -q "JIRA_BACKEND='twg'" "$tmp/state/config.sh"
cp "$tmp/state/config.sh" "$tmp/original"
# A config without a terminal newline is valid input to the runtime parser and
# must remain reconfigurable in both directions while preserving other settings.
config_without_lf=$(cat "$tmp/state/config.sh")
printf '%s' "$config_without_lf" > "$tmp/state/config.sh"
printf '%s\n' rest https://jira.example.test ABC "$tmp/netrc" - | run_wizard >/dev/null 2>&1
grep -q "JIRA_BACKEND='rest'" "$tmp/state/config.sh"
grep -q "PICKER_LAYOUT='top'" "$tmp/state/config.sh"
grep -q 'CACHE_TTL_MIN=10' "$tmp/state/config.sh"
config_without_lf=$(cat "$tmp/state/config.sh")
printf '%s' "$config_without_lf" > "$tmp/state/config.sh"
printf '%s\n' twg https://jira.example.test ABC fictional-site | run_wizard >/dev/null 2>&1
grep -q "JIRA_BACKEND='twg'" "$tmp/state/config.sh"
grep -q "PICKER_LAYOUT='top'" "$tmp/state/config.sh"
grep -q 'CACHE_TTL_MIN=10' "$tmp/state/config.sh"
cp "$tmp/original" "$tmp/state/config.sh"
if printf '%s' '' | run_wizard >/dev/null 2>&1; then exit 1; fi
cmp "$tmp/original" "$tmp/state/config.sh"
if printf '%s\n' invalid | run_wizard >/dev/null 2>&1; then exit 1; fi
cmp "$tmp/original" "$tmp/state/config.sh"
# Fresh setup has the same validation and activation behavior.
printf '%s\n' rest https://jira.example.test ABC "$tmp/netrc" - > "$tmp/input"
run_wizard "$tmp/fresh" < "$tmp/input" > "$tmp/output" 2>&1
grep -q "JIRA_BACKEND='rest'" "$tmp/fresh/config.sh"
if printf '%s\n' invalid | run_wizard "$tmp/cancelled-first" > "$tmp/output" 2>&1; then exit 1; fi
[ ! -e "$tmp/cancelled-first/config.sh" ]
# A failed candidate must not replace the working config.
if (export WIZARD_HTTP=401; run_wizard < "$tmp/input") > "$tmp/output" 2>&1; then
  echo 'wizard accepted rejected credentials' >&2; exit 1
fi
cmp "$tmp/original" "$tmp/state/config.sh"
# Reject symlinked configuration before prompting or touching its target.
mv "$tmp/state/config.sh" "$tmp/target"
ln -s "$tmp/target" "$tmp/state/config.sh"
if run_wizard < "$tmp/input" > "$tmp/output" 2>&1; then echo 'wizard followed config symlink' >&2; exit 1; fi
cmp "$tmp/original" "$tmp/target"
rm "$tmp/state/config.sh"; mv "$tmp/target" "$tmp/state/config.sh"
# Block the probe, edit the live configuration, and ensure activation refuses
# to overwrite that newer edit. The same protection applies to token rotation.
for change in config credential; do
  gate="$tmp/$change"
  (export WIZARD_GATE="$gate"; run_wizard < "$tmp/input") > "$tmp/output" 2>&1 & wizard_pid=$!
  i=0
  while [ ! -e "$gate.started" ] && [ "$i" -lt 300 ]; do sleep 0.02; i=$((i + 1)); done
  [ -e "$gate.started" ] || { kill "$wizard_pid" 2>/dev/null || true; echo 'wizard probe did not start' >&2; exit 1; }
  if [ "$change" = config ]; then
    printf '%s\n' '# concurrent user edit' >> "$tmp/state/config.sh"
  else
    printf '%s\n' 'machine jira.example.test login fictional password rotated' > "$tmp/netrc"
  fi
  cp "$tmp/state/config.sh" "$tmp/expected"
  : > "$gate.release"
  if wait "$wizard_pid"; then echo 'wizard activated after concurrent edit' >&2; exit 1; fi
  cmp "$tmp/expected" "$tmp/state/config.sh"
  grep -q 'changed during validation' "$tmp/output"
done
if find "$tmp/state" -name '.setup-candidate.*' -print | grep -q .; then echo 'wizard left candidate state behind' >&2; exit 1; fi
printf '%s\n' 'ok - setup switching, cancellation, rejected credentials, symlinks, and concurrent edits'
