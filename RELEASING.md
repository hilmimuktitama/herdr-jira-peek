# First-release checklist

This checklist prepares a release; it does not publish one. Keep `0.1.0`
unreleased until every applicable item is verified.

## Preparation

- [x] Confirm the maintainer has authority to publish this repository and that
  employer, contributor, and third-party permissions allow publication.
- [x] Confirm the canonical repository:
  [hilmimuktitama/herdr-jira-peek](https://github.com/hilmimuktitama/herdr-jira-peek).
  The Herdr plugin identifier remains `hlmmkttm.jira-peek`.
- [x] Scan the final tree for secrets, credentials, Jira URLs, issue content,
  private tenant details, and generated data. The 2026-09-07 manual review
  covered source, scripts, docs, and images; no confirmed secrets or private
  tenant data were found. This was not a gitleaks run.
- [ ] Scan Git history for the same items before publication; the final-tree
  scan does not replace a history scan.
- [x] Document the maintainer-selected private vulnerability reporting contact
  in `SECURITY.md`: [hilmimukti@gmail.com](mailto:hilmimukti@gmail.com).
- [x] Document the Code of Conduct reporting contact in `CODE_OF_CONDUCT.md`.
  The maintainer selected the same address for both policies, with distinct
  suggested email subjects for security and conduct reports.
- [ ] Confirm the availability, licensing, terms, privacy, and permission
  requirements of Herdr, TWG, and runtime dependencies (`jq`, `less`, `curl`,
  browser/clipboard utilities, and optional `fzf`), and keep the existing
  notices accurate.
- [x] Run the existing local/CI checks from `CONTRIBUTING.md` and confirm CI is
  green on its supported macOS and Linux jobs. Both passed for `552fd2a` in
  [CI run 34079614103](https://github.com/hilmimuktitama/herdr-jira-peek/actions/runs/34079614103).
  No public publication has occurred.

### Local verification record — 2026-09-07

- [x] Full runtime suite, including final privacy/PAGER, cross-session, and real
  PTY coverage, plus the static manifest and shell syntax checks, passed before
  the final documentation-only change.
- [x] Original owned shellcheck 0.11.0 run passed for
  `config.example.sh scripts/*.sh tests/*.sh`.
- [x] Full CI verification passed on macOS and Linux for `552fd2a`.

The original checks were:

```sh
for file in config.example.sh scripts/*.sh tests/*.sh; do
  sh -n "$file" || exit
done
sh tests/manifest.sh
sh tests/run.sh
```
- [ ] Using an independent Jira site and permitted test account, run a real
  smoke test: setup, successful doctor, then the named `peek` action with an
  allowed issue key in the source pane. Use no work data; remove test state.
- [x] Include [public screenshots](README.md#quick-tour) using entirely
  fictional Jira content and a reserved test hostname. Do not publish real
  issue keys, URLs, descriptions, comments, tokens, or tenant details.

## Real smoke checklist

Using an independent Jira site and permitted test account, verify Herdr >= 0.8.2
and TWG >= 1.2.6, then run setup, doctor, peek, toggle, and refresh with an
allowed issue key. Confirm read-only behavior and remove test state.

The future release install command must use a reviewed immutable `--ref`
reference, for example `herdr plugin install <owner>/<repository> --ref
<reviewed-commit>`; no such release reference exists yet.

## Publication

- [ ] Decide and document the eventual release version, tag, and release notes;
  update version/docs only when publishing. Do not claim an immutable tag
  before it exists.
- [ ] Publish only from the reviewed canonical repository after preparation is
  complete; there is no publish automation in this project.
- [ ] Confirm the selected email inbox receives private vulnerability and
  conduct reports before publication. Email delivery has not been tested here.
- [ ] After publication, verify the documented install path and add the
  `herdr-plugin` topic to the repository if that is the chosen marketplace
  discovery mechanism.

No new runtime features are required for release preparation.
