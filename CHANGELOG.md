# Changelog

## 0.1.0 — Unreleased

- Redesigned the viewer as a compact responsive picker with F1 help, honest
  browser/copy feedback, terminal-size-aware preview layout, resize recovery,
  and a fallback for older fzf versions without footer support.
- Release preparation documents the read-only Jira Cloud scope and keeps
  local publication gates explicit.
- Added a visual README tour, four screenshots of the real terminal UI, and a
  source-and-picker workflow composition, all using fictional issue data.

This project has not published an immutable release tag. The initial release
will provide a narrow, read-only Jira Cloud preview action for Herdr, with
explicit project allowlists, setup/doctor/cache-maintenance actions, and no
default generic link interception. Private temporary state is cleaned on normal
exit and safely reaped after interrupted owner processes disappear.
