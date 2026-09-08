# Changelog

## 0.2.0 — 2026-09-08

First versioned release, including the initial feature set below.

- Keep an independent Peek viewer for each source terminal in a Herdr session.
  Opening Peek on another agent, pane, or workspace preserves existing viewers.
- Toggle only the current source's viewer, or the focused viewer itself, even
  after panes move. Verify terminal identity before closing a reused pane ID.
- Isolate each source's candidates and last-selected issue. Browser actions use
  the current source/viewer selection; background callbacks keep their owner.
- Preserve shared issue caching and serialize concurrent viewer lifecycle changes.
- Close all pre-upgrade viewers before updating from the development version;
  their old tracking cannot reliably identify the source terminal. Stale legacy
  records are removed automatically without closing unrelated viewers.
- Known limitation: the historical intermittent macOS PTY paging-test timeout
  has not been diagnosed. Automated tests use simulated Herdr and Jira services;
  they do not establish live Jira connectivity.

## 0.1.0 — Development baseline (not released)

- Check mandatory fzf, jq, less, and TWG prerequisites during setup, including
  TWG minimum version and authentication/connectivity. Preserve config on reruns.
- Add an interactive dependency installer with per-install approval and separate
  user-managed TWG OAuth login. Refuse to open the picker when TWG is missing.
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
