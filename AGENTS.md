# Public repository data policy

- Never commit or push real Jira, company, customer, or private personal data.
  This includes issue keys and content, tenant URLs, identities, terminal
  output, logs, cache files, configuration, credentials, and screenshot metadata.
- Use entirely fictional data for examples, fixtures, screenshots, and demos.
  Do not copy real records and merely rename, blur, or redact their identifiers.
- Capture documentation screenshots with the isolated fictional fixtures in
  `docs/screenshots/capture.py`. Never capture a live work session or connected
  Jira account for publication.
- Before committing or pushing, inspect the proposed diff and new assets for
  private data. Visually review screenshots and check their metadata. Replace
  any questionable sample with a fresh fictional example before publishing.
- Keep real local configuration and plugin state outside the public repository.
  Never print credentials or private data while verifying these rules.
