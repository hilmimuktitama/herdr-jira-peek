# Third-party notices

Peek for Jira is an unofficial, unaffiliated community plugin. Jira and
Atlassian are trademarks owned by Atlassian.

## Herdr

Peek for Jira runs as a Herdr plugin and uses Herdr's plugin action/pane
interfaces and private plugin state. Herdr is a separate project with its own
license and terms; consult the installed Herdr distribution for its notices.

## Teamwork Graph CLI (TWG)

The plugin calls the official Atlassian Teamwork Graph CLI for read-only Jira
Cloud work-item retrieval. TWG authenticates with Atlassian OAuth and is a
separate, proprietary service/tool with its own license, terms, privacy policy,
availability, and permission model. Peek for Jira does not manage TWG
credentials. Raw responses and stderr may exist transiently in private request
state while a request is running.

The plugin source itself remains available under the MIT License in `LICENSE`.
