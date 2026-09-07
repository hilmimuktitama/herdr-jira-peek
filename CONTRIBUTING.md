# Contributing to Peek for Jira

Thanks for helping improve Peek for Jira. Keep changes focused on the plugin,
documentation, tests, or its public packaging.

This is an unofficial, unaffiliated Jira Cloud plugin. Jira and Atlassian are
Atlassian trademarks. Contributions are accepted under the repository's MIT
license; by submitting a contribution, you grant the project permission to
distribute it under those same MIT terms.

## Prerequisites

- Herdr >= 0.8.2
- TWG >= 1.2.6, configured with Atlassian OAuth via `twg setup` for issue testing
- A POSIX shell, `jq`, and `less`
- `fzf` for testing the interactive picker
- `shellcheck` for the release lint gate

## Local development

Clone the repository, make a change, and link the checkout into Herdr:

```sh
herdr plugin link "$PWD"
```

Run the **Set up Peek for Jira** action from Herdr after linking. Setup copies
from Herdr's `HERDR_PLUGIN_ROOT` and refuses to overwrite an existing config;
it does not run TWG login/setup. Keep a test Jira account and a narrow
`JIRA_PROJECTS` allowlist. Never commit credentials, private tenant details, or
cached issue data. Tests fake external command dependencies and do not require
a live setup.

## Checks

Run the syntax check and test suite before opening a pull request:

```sh
for file in config.example.sh scripts/*.sh tests/*.sh; do
  sh -n "$file" || exit
done
sh tests/run.sh
sh tests/manifest.sh
```

Run the shell lint. `SC1090` is excluded because the entrypoint scripts source
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
herdr plugin list --plugin hlmmkttm.jira-peek --json
```

This changes local Herdr plugin registration and is a manual check, not part
of the test suite. CI runs shell syntax checks, tests, and shellcheck only; it
does not install Herdr or validate the manifest.

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
