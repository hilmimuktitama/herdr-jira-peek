# Changelog

## 0.1.0 — Unreleased

Initial release planned; no release tag has been published.

- Scan the current Herdr pane for Jira Cloud issue keys, with an explicit
  project allowlist and a capped, deduplicated candidate list.
- Filter issues by key, status, or summary in an adjacent responsive picker.
  Preview descriptions and comments, or open a full-screen reader.
- Rescan the source pane, refresh an issue, open Jira in the browser, and copy
  keys or links using keyboard controls. F1 shows additional help.
- Retrieve issue data through the official TWG CLI and its OAuth connection.
  Jira operations are read-only; there is no generic link interception.
- Configure the plugin with setup and doctor actions, an adjustable issue-cache
  TTL, and an action to clear cached issue files. See [data retention and cleanup
  limits](SECURITY.md) for state retained outside the cache.
- Use a numbered issue menu when fzf is unavailable and batch metadata loading
  when progressive picker updates are unavailable.
- Follow a visual README tour using fictional Jira data, including four UI
  screenshots and a source-and-picker workflow composition.
