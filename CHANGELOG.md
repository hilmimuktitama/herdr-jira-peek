# Changelog

## 0.2.3 — 2026-09-08

- Add `PICKER_LAYOUT='top'|'bottom'` configuration. Default to bottom alignment
  to reduce eye travel, with the newest issue and filter near the terminal
  prompt, with older issues above and the preview above the list at every width.
  Keep `top` available as an explicit choice. Validate the setting in the
  runtime and doctor, and apply changes on reopening.
- Keep the picker responsive during continuous pane resizing by calculating
  resize layout changes in the background. Restore issue content when the pane
  grows again and keep Esc usable in small panes.
- Update the README with the bottom-aligned experience and reproducible
  screenshots using entirely fictional, isolated fixtures. Document the public
  repository's fictional-data requirement for examples, tests, and screenshots.

## 0.2.2 — 2026-09-08

- Make ticket navigation and filtering responsive by removing runtime setup and
  cache sweeps from selection and shortcut callbacks. Use the native fzf counter
  and POSIX callback shell, and initialize cached previews only once.
- Sweep expired cache files in one pass instead of starting a process per ticket.
- Clear browser and clipboard action feedback automatically in live pickers,
  restoring preview space. Changing the filter or selected issue also dismisses
  feedback, including in older pickers.
- Highlight `Ctrl-G Rescan` in the quick guide for finding issues in new source
  output. Browser opening remains available with `Ctrl-O` and in F1 Help.
- Start short issues at the top of the full-screen reader instead of leaving
  blank space above the content.

## 0.2.1 — 2026-09-08

- Show quiet opening feedback before scanning the source pane. Show immediate
  rescan progress and keep modern fzf pickers responsive until the scan finishes.
- Keep every detected issue key searchable, including keys beyond the first 20.
  `MAX_CANDIDATES` now limits automatic metadata loading only; older issues load
  their preview when selected. The same behavior applies when rescanning.

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
