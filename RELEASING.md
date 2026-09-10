# Release checklist

Canonical repository: [hilmimuktitama/herdr-jira-peek](https://github.com/hilmimuktitama/herdr-jira-peek).
Plugin ID: `jira-peek`.

The repository became public on 2026-09-07. Version `0.2.0` was published on
2026-09-08 as the first versioned release; `0.1.0` was the development baseline.
The latest release is `0.2.4`, published on 2026-09-10. This project has no
publish automation.

## Before making the repository public

- [x] Record maintainer confirmation of authority to publish, including
  employer, contributor, and third-party permissions.
- [x] Include the MIT license, contribution terms, security policy, and Code of
  Conduct. GitHub private vulnerability reporting is enabled. The maintainer
  approved publishing [hilmimukti@gmail.com](mailto:hilmimukti@gmail.com) for
  conduct reports and as an alternative security-reporting contact.
- [x] Document local pane capture, retained issue keys, cache behavior, and
  interrupted-process cleanup limits in [SECURITY.md](SECURITY.md).
- [x] Add upstream setup, permission, privacy, and terms references in
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [x] Review the tree and Git history selected for publication for secrets,
  private tenant details, issue content, and generated state. The documentation
  cleanup was published as `5cebf44`; scan scope is recorded below.
- [x] Set the GitHub description and the `herdr-plugin`, `jira`, and `terminal`
  topics; verified on 2026-09-07 while the repository remained private.
- [x] Make the repository public and remove the private-access note from README.
  Anonymous GitHub API access confirmed public visibility and the expected
  `main` commit; the anonymously fetched root manifest matched the checkout.
  Installation itself was not rerun.
- [ ] Confirm marketplace discovery after publication. Herdr indexes public
  repositories with the `herdr-plugin` topic and a valid manifest on the default
  branch; listing is automatic and is not an endorsement. See the
  [marketplace documentation](https://herdr.dev/docs/marketplace/).
  Eligibility is confirmed: the repository is public, has the topic and root
  manifest, and is neither a fork nor archived. It was absent from the published
  index generated at `2026-09-07T13:31:08.853Z`; listing awaits a later refresh.

## Maintainer follow-up

- [ ] Confirm the applicable dependency terms and organizational permissions
  for the intended distribution; the recorded authority to publish and upstream
  links are not an independent verification of each agreement.
- [ ] Confirm the reporting inbox receives private security and conduct reports;
  delivery has not been independently tested.

## Plugin identity

The plugin now uses the neutral ID `jira-peek`. Existing users must follow
[the migration guide](README.md#migrate-from-the-old-plugin-id) to replace the
old registration and action bindings. GitHub ownership is unchanged. The
maintainer uses a GitHub noreply address for future commits from this checkout;
previous public commit history has not been rewritten.

## Version 0.2.4 release validation — 2026-09-10

- [x] Run live-picker rescans in a dedicated worker, preserve scans across
  resizing, ignore repeated requests while busy, and retain the intentional
  opening notification. Keep unchanged snapshots from restarting previews.
- [x] Validate scrollback keys in one pass. A local fictional sample with 4,002
  key occurrences took about 12.1 seconds before the change and 0.12 seconds
  after it. These are scan-helper measurements, not live Jira timings.
- [x] Pass local shell syntax, manifest contract, ShellCheck 0.11.0, and the
  complete runtime suite with real fzf/less/Expect PTY coverage on retry.
  One local macOS rapid-resize check timed out; its cause remains undiagnosed,
  and the passing retry does not establish a fix.
- [x] Review the release diff for private data. Gitleaks 8.30.1 found no leaks
  in the prospective tree or release commit. No screenshots or runtime data
  were added; regression fixtures contain fictional issue data only.
- [x] Verify Linux and macOS CI on release commit
  `caef80029507a15096357cf258f4c64917e107b6`: both jobs passed in
  [run 34454111594](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34454111594).
- [x] Publish [v0.2.4](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.2.4)
  from that commit and pin README installation to its full SHA with `--ref`.
  The subsequent documentation commit records publication; it changes no runtime code.

The source-terminal flicker reported when opening a Herdr split remains
unresolved. This release does not claim a fix, and no live Jira account or
existing user Herdr pane was used for validation.

## Version 0.2.3 release validation — 2026-09-08

- [x] Keep the picker responsive during continuous pane resizing and restore
  the preview when space returns. Real terminal tests cover both layouts,
  shrinking to 1×1, a burst of 180 resizes, and Esc in a small pane during a scan.
- [x] Default to bottom alignment, with the newest issue and filter near the
  source terminal's current output. Preserve the original layout through
  `PICKER_LAYOUT='top'`; validate both choices in runtime and doctor.
- [x] Pass local shell syntax, manifest contract, ShellCheck 0.11.0, and the
  complete runtime suite, including real fzf/less/Expect PTY coverage.
- [x] Review the publication diff and new screenshots for private data.
  Gitleaks 8.30.1 found no leaks in the prospective release tree. All eight PNGs
  contain only image chunks, with no extra metadata or trailing data. The three
  new screenshots use isolated fictional fixtures and were visually reviewed.
- [x] Verify Linux and macOS CI on release commit
  `3b103d3226bffad78ebefae2767a232dc414a04a`: both jobs passed in
  [run 34236555328](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34236555328).
- [x] Publish [v0.2.3](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.2.3)
  from that commit and pin README installation to its full SHA with `--ref`.
  The subsequent documentation commit records publication; it changes no runtime code.

## Version 0.2.2 release validation — 2026-09-08

- [x] Remove full runtime initialization and cache sweeps from navigation and
  shortcut callbacks; use the native fzf counter and POSIX callback shell.
- [x] Initialize cached previews once and sweep expired cache files in one
  pass, preserving nested files, symlinks, and zero-TTL behavior.
- [x] Add expiring browser/clipboard feedback, promote Ctrl-G Rescan in the
  quick guide, and start short issues at the top of the full-screen reader.
- [x] Pass local shell syntax, manifest contract, ShellCheck 0.11.0, and the
  complete runtime suite, including real fzf/less/Expect PTY coverage.
- [x] Measure synthetic 100-ticket helper medians of about 13 ms for selection
  (previously 400 ms) and 122 ms for cached previews (previously 801 ms).
  The terminal arrow/filter burst improved from 947 ms to about 200–270 ms.
  These are local fixture measurements, not live Jira or concurrent-agent tests.
- [x] Verify Linux and macOS CI on release commit
  `ffc3e13517bf3e9d9ebbd451c4abbcf89c8f03f7`: both jobs passed in
  [run 34231248783](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34231248783).
- [x] Publish [v0.2.2](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.2.2)
  from that commit and pin README installation to its full SHA with `--ref`.
  The subsequent documentation commit records publication; it changes no runtime code.

## Version 0.2.1 release validation — 2026-09-08

- [x] Keep all detected keys searchable while limiting automatic metadata
  loading, with regression coverage for an older key in a 105-key pane.
- [x] Add quiet opening feedback and immediate rescan progress, with real
  terminal coverage for responsive help, rapid rescans, and cancellation.
- [x] Pass local shell syntax, manifest contract, ShellCheck 0.11.0, and the
  complete runtime suite, including real fzf/less/Expect PTY coverage.
- [x] Verify Linux and macOS CI on release commit
  `eed721c57ee6330b4ee84086bc631c39e5f462fb`: both jobs passed in
  [run 34222136518](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34222136518).
- [x] Publish [v0.2.1](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.2.1)
  from that commit and pin README installation to its full SHA with `--ref`.
  The subsequent documentation commit records publication; it changes no runtime code.

Regression fixtures use simulated Jira and Herdr services and fictional issue
content. Existing configuration remains compatible; close and reopen viewers
after updating. The historical intermittent macOS PTY paging timeout recorded
below remains an undiagnosed limitation.

## Version 0.2.0 release validation — 2026-09-08

- [x] Set the manifest version and changelog to `0.2.0`, including independent
  viewers per source terminal, source-scoped selection, and upgrade handling.
- [x] Pass local shell syntax, manifest contract, and ShellCheck 0.11.0 checks.
- [x] Pass the full runtime suite, including real fzf/less/Expect PTY coverage
  and the new multi-pane lifecycle, ownership, movement, failure, concurrency,
  and legacy-upgrade regressions. Expect required execution outside the local
  sandbox to create its PTY; the sandboxed attempt could not run that check.
- [x] Explicitly retain the historical intermittent macOS PTY paging timeout
  as an undiagnosed limitation. This run passed; it does not establish a fix.
- [x] Verify Linux and macOS CI on release commit
  `952fd6eba081810d79268bed5ec5fa46f32d2a1d`: both jobs passed in
  [run 34179987128](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34179987128).
- [x] Publish [v0.2.0](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.2.0)
  from that commit and pin README installation to its full SHA with `--ref`.
  The subsequent documentation commit records publication; it changes no runtime code.

No live Jira site or existing user Herdr panes were used for this release's
validation. Lifecycle tests use simulated Herdr responses and fictional keys.

## Review evidence — 2026-09-07

- Prepublication baseline CI: both `shell (ubuntu-latest)` and `shell (macos-latest)`
  passed for `829e3c01c2a5d8c85c66212e262f9bca2c6b5d34` in
  [run 34082990613](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34082990613).
  This is evidence for that commit, not for later edits.
- Gitleaks 8.30.1 found no leaks in the publication working files or Git history
  through `5cebf44` (seven commits, using `--all --reflog`). Manual review of historical
  filenames and URL hosts found no confirmed private configuration or real
  Jira tenant URLs. Scanner results are supporting evidence, not a guarantee.
- All five screenshots were visually reviewed: they use fictional issue data
  and example identities. The reader uses `jira.example.test`. PNG inspection
  found only image chunks, with no extra metadata or trailing data. Relative
  Markdown file targets resolved.
- Public-release documentation was reviewed against the source and official
  dependency documentation. Functional testing was excluded from this review.

## Historical validation — 2026-09-07

- The earlier preparation record reports passing local runtime, PTY, privacy,
  cross-session, shell syntax, static manifest, and ShellCheck 0.11.0 checks.
  Both CI platforms passed for `552fd2a` in
  [run 34079614103](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34079614103).
- The macOS PTY paging check intermittently timed out. The run for `bce0234`
  passed on retry, and five local PTY runs passed; the cause remained unresolved.
  See [run 34080079774](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34080079774).
  Later successful runs do not establish that the cause was fixed.
- The maintainer confirmed that the installed plugin was tested and works.
  No private site details, issue data, or configuration were collected for that
  record.

Future live smoke checks should use an independent Jira site and permitted
test account. Follow the documented requirements, exercise setup, doctor,
peek, toggle, and refresh with an allowed key, and remove test state afterward.
