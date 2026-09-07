# Peek for Jira Security Policy

Peek for Jira is an unofficial, unaffiliated community plugin for Jira Cloud.
Jira and Atlassian are Atlassian trademarks. This plugin is MIT-licensed and
does not manage credentials; Atlassian OAuth authentication is handled outside
the plugin by the official TWG CLI.

## Reporting a vulnerability

Please do not disclose vulnerabilities in a public issue. Use GitHub private
vulnerability reporting once it is enabled for the published repository.
Maintainers must enable and test that private reporting channel before the first
public release.

Include the affected version, a concise description of the impact, reproduction
steps, and any suggested mitigation. Redact Jira URLs, issue content,
credentials, tokens, and other sensitive data from the report.

## Jira data and local cache

The picker requests capped metadata in one batch and keeps it only in its
private viewer directory. Full descriptions and comments are fetched lazily
for a preview and cached in Herdr's private plugin state for the configured
TTL. Expired entries are deleted on invocation; `CACHE_TTL_MIN=0` uses a
temporary render file and leaves no durable issue cache entry. A refresh
removes the selected entry before fetching a replacement. Protect the plugin
state directory and do not share cache files in bug reports. The plugin only
reads Jira data and never mutates Jira work items.

Raw TWG responses and stderr can exist transiently in private request state
while a request is running; they are not intended as durable plugin data or
displayed diagnostic text. Fetch and viewer temporaries include their owner
process ID. Normal exits and
handled signals remove them immediately; a later invocation removes abandoned
entries after confirming that the recorded process is no longer running.

Diagnostics use fixed local labels and do not display arbitrary TWG text. Older
persisted diagnostic artifacts are purged during startup; this does not make raw
request response or stderr bytes a permanent-storage guarantee.

The `doctor` action is read-only and never runs login/setup or prints TWG
output. The `clear-cache` action removes only regular files directly inside
Peek for Jira's issue-cache directory; it does not recurse through unrelated
state.

`config.sh` is parsed as a small allowlist of setting assignments and is never
executed as shell code. Config, state, cache, and diagnostic paths are rejected
when their final path component is a symlink.
