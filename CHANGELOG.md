# Changelog

## 0.1.0 — Unreleased

Initial release planned; no release tag has been published.

- Use the neutral plugin ID `jira-peek`. Existing development installations
  need to [migrate their registration, settings, and bindings](README.md#migrate-from-the-old-plugin-id).
- Accept security reports through GitHub private vulnerability reporting,
  with the maintainer's public email retained as an alternative.
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
- Require fzf for the picker; setup explains installation, doctor fails when
  it is missing, and peek reports the dependency before opening a split.
- Retain a numbered recovery menu for fzf startup errors and batch metadata
  loading when progressive picker updates are unavailable.
- Recommend an explicit `prefix+i` keybinding to avoid Alt key handling issues.
- Follow a visual README tour using fictional Jira data, including four UI
  screenshots and a source-and-picker workflow composition.
