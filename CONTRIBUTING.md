# Contributing to Peek for Jira

Thanks for helping improve Peek for Jira. Keep changes focused on the plugin,
documentation, tests, or its public packaging.

This is an unofficial, unaffiliated Jira Cloud plugin. Jira and Atlassian are
Atlassian trademarks. Contributions are accepted under the repository's MIT
license; by submitting a contribution, you grant the project permission to
distribute it under those same MIT terms.

## Prerequisites

- [Herdr](https://herdr.dev/docs/install/) >= 0.8.2 for linking and manual use
- [TWG](https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/)
  >= 1.2.6, configured with Atlassian OAuth for live Jira use
- A POSIX shell, `jq`, and `less`
- `fzf` for running the plugin; `expect` for interactive PTY coverage (with `less`)
- ShellCheck 0.11.0 for the release lint gate (the version pinned in CI)

## Local development

Clone the repository, make a change, and link the checkout into Herdr:

```sh
herdr plugin link "$PWD"
```

Run the **Set up Peek for Jira** action from Herdr after linking. Setup copies
from Herdr's `HERDR_PLUGIN_ROOT`, preserves existing config, and checks tools
and TWG authentication/connectivity. The separate dependency installer asks
before installing tools and skips TWG login; run `twg setup` yourself. Keep a
test Jira account and a narrow
`JIRA_PROJECTS` allowlist. Never commit credentials, private tenant details, or
cached issue data. Automated tests fake Herdr and TWG, so they do not require
either CLI, credentials, or a live Jira site. Some checks use real `fzf`,
`less`, and `expect` binaries.

`sh tests/dependencies.sh` checks setup and the installer with isolated fake
tools. Its approval-path checks use `expect`; no real packages, downloads, or
OAuth sessions are used by these tests.

## Checks

Run the syntax check and test suite before opening a pull request:

```sh
for file in config.example.sh scripts/*.sh tests/*.sh; do
  sh -n "$file" || exit
done
sh tests/run.sh
sh tests/manifest.sh
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
shellcheck -s sh -e SC1090 config.example.sh scripts/*.sh tests/*.sh
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
dependencies, TWG version/authentication, and site access. Doctor never prints
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
