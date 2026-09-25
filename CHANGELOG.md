# Changelog

## 0.4.2 — 2026-09-25

- Scan recognized agent panes through passive visible and detection snapshots.
  Herdr can scroll an idle full-screen agent while fulfilling a recent-history
  read, so initial opening and Ctrl-G no longer request that read from agents.
  Ordinary terminal panes still include recent unwrapped scrollback.

## 0.4.1 — 2026-09-23

- Reflow the retained preview during pane resizing, preserving the filter,
  selection, and reading position without restarting the renderer or Jira work.
- Keep long paragraphs and unbroken Unicode text pageable with a bounded
  reading width. Use native word wrapping where available and hide the preview
  when the pane is too small to read it.
- Open quietly during fast scans; show progress only for slower scans and
  cancel pending feedback before opening, including a blocked notification.
- Correct the space reserved for expanded help. Cover scrolled resizing,
  long paragraphs, refresh isolation, tiny-pane recovery, and rapid divider
  drags with real fzf terminal regressions and fictional data.
- Simplify the README around setup, daily controls, and configuration. Remove
  obsolete migration and billing notes, and link detailed guidance separately.
- Preserve the startup redraw workaround for initial clipping on older Herdr
  versions. Source-pane flicker during split creation remains a host-level
  investigation; this change does not claim to resolve it fully.

## 0.4.0 — 2026-09-23

- Add ordered field configuration for the picker, preview, and reader, including
  Jira custom fields and friendly labels.
- Add an offline Customize action with presets, a fictional preview, validation,
  and atomic save/cancel behavior that preserves connection settings.
- Keep terminal-native colors, with optional plain text and an authoritative
  `NO_COLOR` override. Keep picker rows and detail metadata compact.
- Document workflow-based setup and configuration for users and their AI agents.
- Request configured fields through TWG and REST, skip supplemental comments
  when hidden in both detail views, and track field coverage in cached issues.

## 0.3.0 — 2026-09-19

- Add an explicit optional Jira Cloud REST backend with external netrc
  credentials. TWG remains the default; REST never silently falls back to TWG.
- Add staged connection activation, hashed connection markers, flat-cache
  invalidation, and stale viewer callback protection for backend/account changes.
- Keep the picker, reader, refresh, rescan, browser, and clipboard controls
  consistent across backends, including paginated REST comments.
- Validate setup before replacing the active configuration. Preserve it on
  cancellation, failed authentication, missing dependencies, or concurrent edits.
- Invalidate cached data on observed authentication rejection and prevent
  pending requests from restoring cache after a connection change or clear.
- Avoid redundant preview refreshes that could duplicate Jira requests, and
  clean up connection state left by cancelled preview workers.
- Cover REST errors, credential rotation, setup recovery, and connection
  isolation with fictional offline regression fixtures.

## 0.2.5 — 2026-09-13

- Clear the entire filter with Ctrl-U, including from the middle of the query.
  Prioritize the clear shortcut in narrow panes and document filter editing in
  F1 Help. Preview scrolling remains on PgUp/PgDn; Ctrl-D scrolls down half a page.
- Synchronize a newly opened viewer's terminal size with Herdr's pane geometry.
  This prevents Herdr 0.9.0 from clipping the selected issue and bottom filter
  until the first mouse or keyboard input, without moving the split divider.
- Stop picker navigation at the first and last matching issue so short filtered
  lists do not loop while scrolling. Keep preview scrolling unchanged.

## 0.2.4 — 2026-09-10

- Run Ctrl-G rescans in a dedicated worker when the live picker connection is
  available. Keep navigation and filtering responsive during source reads,
  preserve scans across pane resizing, and ignore repeated requests until the
  current scan finishes.
- Build and serialize picker snapshots in the background. Update only the
  status when results are unchanged and avoid duplicate preview refreshes.
- Validate detected issue keys in one pass instead of starting a process for
  every occurrence in terminal output, speeding up initial scans and rescans.
- Preserve the intentional opening notification. This release does not claim
  to fix the reported source-terminal flicker when Herdr opens a split.
- Extend fictional-fixture coverage for repeated scrollback keys, unchanged
  results, and resizing during a blocked scan. Make the resize stress test
  observe a distinct size before checking restoration.
- Known validation limitation: the local macOS rapid-resize terminal test
  intermittently times out. Its cause remains undiagnosed.

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
- Use the neutral plugin ID `jira-peek`.
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
