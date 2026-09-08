# Peek for Jira Security Policy

Peek for Jira is an unofficial, unaffiliated community plugin for Jira Cloud.
Jira and Atlassian are Atlassian trademarks. This plugin is MIT-licensed and
does not manage credentials; Atlassian OAuth authentication is handled outside
the plugin by the official TWG CLI.

The optional `install-dependencies` action opens an interactive terminal and
requires approval before running a package manager or Atlassian's TWG
installer. The latter is downloaded from Atlassian over HTTPS and executed
with `--skip-login --skip-skills`; the upstream installer manages TWG files and
may update shell PATH configuration. Installation runs locally with the user's
permissions; Linux package managers may request sudo. Setup checks capture no
credentials and discard TWG authentication diagnostics instead of printing them.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/hilmimuktitama/herdr-jira-peek/security/advisories/new)
to send a security report to the maintainers. You can also email
[hilmimukti@gmail.com](mailto:hilmimukti@gmail.com) with the subject
"Peek for Jira security report". The maintainer has chosen to publish this
contact address. Do not disclose vulnerabilities in a public issue.

Include the affected version, a concise description of the impact, reproduction
steps, and any suggested mitigation. Redact Jira URLs, issue content,
credentials, tokens, and other sensitive data from the report.

## Jira data and local cache

The plugin only reads Jira data. Its project allowlist limits the issue keys
sent to TWG; it does not restrict TWG's OAuth permissions or redact the local
terminal capture used to find keys. TWG authentication and organization
permissions are managed separately; see [third-party notices](THIRD_PARTY_NOTICES.md).

| Data | Storage and retention |
| --- | --- |
| Source pane output | Written to private scan files before extracting keys. May contain unrelated terminal content. Removed on normal scan exit or handled signals. |
| Picker metadata | A capped batch of summaries, statuses, assignees, and update times is requested. Viewer files are removed on normal viewer exit. |
| Full issue JSON | Fetched lazily for a selected preview or reader. With a positive TTL, stored in the issue cache; expired files are purged at runtime startup. With `CACHE_TTL_MIN=0`, a temporary render file is used instead. |
| Selection and bookkeeping | Each source terminal's last selected key, initial candidate list, pane tracking, cache-generation filenames, and diagnostic filenames can persist outside the issue cache. Some contain issue keys. |

Source selection and tracking are stored under the current session's
`sources/source-<terminal-id>/` directory. They can remain after a source or
viewer closes. The issue cache is shared across sources and sessions, so
refreshing or clearing an issue affects that shared cache.

A refresh removes the selected cached issue before fetching a replacement.
`clear-cache` removes only regular files directly inside the issue-cache
directory. Neither it nor `CACHE_TTL_MIN=0` removes selection or bookkeeping
state, active viewer files, or every abandoned temporary file.

## Temporary data and interrupted processes

Raw TWG responses and stderr are captured in private local files while a
request runs. The scanner similarly captures the source pane's full output
locally, but sends only validated issue keys to TWG. Normal exits and handled
signals clean these temporary files.

Forced termination, such as SIGKILL or a system crash, can bypass cleanup.
Later runtime startup reaps recognized PID-stamped TWG fetch files once their
owner is gone, and abandoned viewer directories in the current Herdr session.
It does not reap every temporary file type or every other session's viewer
directory. In particular, `.scan.*` and `.scan-all.*` directories can remain
with pane text or extracted keys. The doctor's temporary
`peek-for-jira-doctor.*` output file in the system temporary directory also
has no startup reaper. Cache TTL is not a retention limit for these files.

Persisted fetch diagnostics use fixed labels rather than arbitrary TWG text;
obsolete diagnostic contents are purged at runtime startup. Diagnostic
filenames can still identify issues. The `doctor` action never runs login/setup
or prints captured TWG output.

## Local data cleanup

Protect the plugin's config and state directories and do not attach their
contents, raw terminal captures, or temporary request files to bug reports.
Use the state directory Herdr supplies to plugin processes as
`HERDR_PLUGIN_STATE_DIR`, rather than guessing a path. For a full local reset,
close all Peek viewers and let plugin actions finish across Herdr
sessions, then remove only this plugin's identified state directory. This also
removes the last selection and tracking information. Inspect the system
temporary directory separately for abandoned `peek-for-jira-doctor.*` files
owned by you. Do not remove files belonging to an active process.

Config and state may share a directory in custom setups; preserve `config.sh`
if you intend to keep your settings. Plugin uninstallation should not be
treated as proof that all local data has been erased. Herdr's own terminal
history, TWG-managed files, backups, and clipboard contents are outside this
plugin's cache cleanup.

`config.sh` is parsed as an allowlist of setting assignments and is never
executed as shell code. The config file and main config, state, cache, and
diagnostic directories are rejected when their final path component is a
symlink.
