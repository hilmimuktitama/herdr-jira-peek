# Contributing to Peek for Jira

Thanks for helping improve Peek for Jira. Keep changes focused on the plugin,
documentation, tests, or its public packaging.

This is an unofficial, unaffiliated Jira Cloud plugin. Jira and Atlassian are
Atlassian trademarks. Contributions are accepted under the repository's MIT
license; by submitting a contribution, you grant the project permission to
distribute it under those same MIT terms.

## Public examples and screenshots

Use entirely fictional data in documentation, fixtures, demos, and screenshots.
Never commit or push real Jira or company data, customer information, private
identities, tenant URLs, terminal output, caches, logs, or credentials. Renaming
or blurring real records does not make them suitable examples.

Use the [offline screenshot capture](docs/screenshots/README.md) instead of a
live work session. Before publishing, inspect the diff, visually review new
images, and check image metadata for private information.

## Prerequisites

- [Herdr](https://herdr.dev/docs/install/) >= 0.8.2 for linking and manual use
- [TWG](https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/)
  >= 1.2.6, configured with Atlassian OAuth for live Jira use (default backend),
  or `curl` plus a private mode-600 netrc for the REST backend
- A POSIX shell, `jq`, and `less`
- `fzf` for running the plugin; `expect` for interactive PTY coverage (with `less`)
- Python 3.9 or newer is optional for the experimental source-terminal highlight
- ShellCheck 0.11.0 for the release lint gate (the version pinned in CI)

## Local development

Clone the repository, make a change, and link the checkout into Herdr:

```sh
herdr plugin link "$PWD"
```

Run the **Set up Peek for Jira** action from Herdr after linking. Setup stages
the existing config or the plugin's template, checks tools and the selected
backend's authentication/connectivity, and activates only a valid candidate.
The separate dependency
installer asks before installing tools and skips TWG login; run `twg setup`
yourself for TWG, or configure an external netrc for REST. Keep a test Jira account and a narrow
`JIRA_PROJECTS` allowlist. Never commit credentials, private tenant details, or
cached issue data. Automated tests fake Herdr and the transport, so they do not
require either CLI, credentials, or a live Jira site. Some checks use real `fzf`,
`less`, and `expect` binaries.

The optional `SOURCE_HIGHLIGHT='auto'` feature uses the patched Herdr native
decoration API and Python 3.9 or newer to mark the selected issue key in the
source pane. It defaults to off and reports unsupported servers. Selection is
checked every 0.2 seconds; Herdr matches rendered cells on each redraw without
reading terminal text through the API. For manual verification, use a disposable
local Herdr pane containing only fictional keys such as `ABC-123`. Check selection
changes, filter changes, no visible match, pane resize/scroll, Unicode before a
key, and viewer close. Stock Herdr requires the [native patch](native/README.md).
Confirm the mark clears when the selection changes or the viewer exits, and that
the source process receives no input and the viewport does not move. Unsupported
capability must leave the source display alone and keep the picker usable.
Never use a connected work terminal or capture live Jira
output for documentation.

Connection lifecycle behavior follows staged activation, connection ID,
flat-cache invalidation, and viewer epoch acceptance cases in
[`docs/connection-lifecycle-plan.md`](docs/connection-lifecycle-plan.md).

`sh tests/dependencies.sh` checks setup and the installer with isolated fake
tools. Its approval-path checks use `expect`; no real packages, downloads, or
OAuth sessions are used by these tests.

## Checks

Run the syntax check and test suite before opening a pull request:

```sh
for file in config.example.sh scripts/*.sh tests/*.sh native/*.sh; do
  sh -n "$file" || exit
done
sh tests/run.sh
sh tests/manifest.sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/highlight-socket.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/highlight-worker.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/highlight-integration.py
sh tests/highlight-ui.sh
```

Install `fzf`, `less`, and `expect` for complete interactive coverage. The PTY
checks are skipped when any of these is unavailable; the real-fzf option
check is also skipped when fzf is absent. A successful run with skipped checks
does not establish full coverage.

Run the shell lint with ShellCheck 0.11.0. CI installs checksum-verified
upstream binaries on both macOS and Linux to keep lint results consistent.
`SC1090` is excluded because the entrypoint scripts source
their checked-in helper through a path resolved at runtime:

```sh
shellcheck -s sh -e SC1090 config.example.sh scripts/*.sh tests/*.sh native/*.sh
```

The supported local pager is `less`; `PAGER` is not an alternative requirement.

## Manual Herdr manifest check

Use [Herdr's documented plugin commands](https://herdr.dev/docs/plugins/) to
inspect the linked manifest:

```sh
herdr plugin link "$PWD"
herdr plugin list --plugin jira-peek --json
```

This changes local Herdr plugin registration and is a manual check, not part
of the test suite. CI runs shell syntax checks, static manifest contract checks
(`tests/manifest.sh`), the runtime suite, and ShellCheck on macOS and Linux.
It does not install Herdr or validate the manifest through Herdr itself.

For an installed plugin, run **Check Peek for Jira** to verify config, state,
dependencies, selected-backend authentication, and site access. Doctor never prints
credentials or issue content and never runs `twg setup`.

## Pull requests

- Keep each pull request scoped to one behavior, fix, or documentation change.
- Explain user-visible behavior and include the relevant test or verification
  results.
- Update public documentation when commands, controls, requirements, or
  privacy behavior change.
- Do not include Jira content, credentials, generated state, or unrelated
  formatting changes.

By contributing, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Navigation performance

Run `python3 tests/benchmark.py` for optional local helper timings with 1, 20,
and 100 synthetic cached issues. It uses temporary state and never contacts
Jira. Output includes median and maximum milliseconds over ten warmed samples;
these measure helper processes, not screen-paint latency. Compare older
checkouts with `--root /path/to/checkout --legacy-focus`.

The PTY regression also reports the time for an arrow/filter burst to save the
final selected key. Timing varies with machine load, so CI checks behavior
rather than a fixed millisecond threshold. Keep configuration parsing, cache
maintenance, and network access out of synchronous selection and typing callbacks.

With the [native Herdr patch](native/README.md) built, run the ANSI rendering
regression (install `pyte` in your test environment):

```sh
HERDR_NATIVE_TEST_BIN="$PWD/.local/bin/herdr-peek" python3 tests/highlight-live.py
```

This creates an isolated Herdr server and PTY with fictional text. It checks the
actual emitted ANSI cell backgrounds, selection changes, source-text preservation,
Unicode placement, alternate-screen redraws, ownership, and lease expiry. It
requires local socket/PTY access and never connects to your live Herdr session.
Also visually verify selection, output updates, and close/reopen in the target
terminal using fictional fixtures from `docs/screenshots/capture.py`. A transport
acknowledgement alone is not evidence of visible highlighting.
