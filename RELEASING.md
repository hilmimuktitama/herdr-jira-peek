# Release checklist

Canonical repository: [hilmimuktitama/herdr-jira-peek](https://github.com/hilmimuktitama/herdr-jira-peek).
Plugin ID: `jira-peek`.

The repository became public on 2026-09-07. `0.1.0` remains unreleased, with
no tags or releases. Making the source public and publishing a versioned
release are separate steps. This project has no publish automation.

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

## Before publishing a versioned release

- [ ] Select the release commit and version, update the manifest and changelog,
  and review the final release notes.
- [ ] Confirm checks for the selected release commit using
  [CONTRIBUTING.md](CONTRIBUTING.md#checks). Keep any known limitations explicit.
- [ ] Resolve or explicitly document the intermittent macOS PTY paging timeout
  described in the historical record below.
- [ ] Publish the tag and release from the canonical repository, then update
  README's release status and installation command to use the full reviewed
  commit SHA with `--ref`. Keep the human-readable version/tag in the release
  notes; a full commit SHA identifies the immutable source revision.

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
