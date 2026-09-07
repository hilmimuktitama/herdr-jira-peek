# Third-party notices

Peek for Jira is an unofficial, unaffiliated community plugin. Jira and
Atlassian are trademarks owned by Atlassian.

## Herdr

Peek for Jira runs as a Herdr plugin and uses Herdr's plugin action/pane
interfaces and private plugin state. Herdr is a separate project with its own
license and notices. See the [Herdr project](https://github.com/herdrdev/herdr),
its [Apache 2.0 license](https://github.com/herdrdev/herdr/blob/master/LICENSE),
and [installation documentation](https://herdr.dev/docs/install/). Consult the
installed distribution for notices applying to that version.

## Teamwork Graph CLI (TWG)

The plugin calls the official Atlassian Teamwork Graph CLI for read-only Jira
Cloud work-item retrieval. TWG authenticates with Atlassian OAuth and is a
separately distributed tool and service with its own terms, privacy policy,
availability, and permission model. Peek for Jira does not manage TWG
credentials. Raw responses and stderr may exist transiently in private request
state while a request is running; see [local retention and cleanup](SECURITY.md).

- [Official setup guide](https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/)
- [Organization permissions and IP restrictions](https://developer.atlassian.com/cloud/twg-cli/getting-started/configure-permissions/)
- [Atlassian Privacy Policy](https://www.atlassian.com/legal/privacy-policy)
- [Atlassian Developer Terms](https://developer.atlassian.com/platform/marketplace/atlassian-developer-terms/),
  linked from the TWG documentation. Follow the terms and consent presented by
  your installed TWG version and Atlassian account for the applicable agreement.

Peek's read-only operations do not imply that the TWG OAuth connection is
limited to read permissions. Organization settings control what TWG may
request; the configured Jira user must also have access to the relevant data.

## Other runtime tools

These tools are installed separately, rather than bundled with the plugin:

| Tool | Purpose | Upstream reference |
| --- | --- | --- |
| jq | JSON parsing and rendering | [Copyright and license notices](https://github.com/jqlang/jq/blob/master/COPYING) |
| less | Full-screen issue reader | [Project and source distributions](https://www.greenwoodsoftware.com/less/download.html) |
| fzf (optional) | Searchable picker | [License](https://github.com/junegunn/fzf/blob/master/LICENSE) |
| curl (optional) | Local socket notifications for progressive picker updates | [Copyright and license](https://curl.se/docs/copyright.html) |

Git, shell utilities, and browser/clipboard commands come from the user's
system or package manager. Their installed distributions provide the relevant
notices. The plugin uses `open`/`pbcopy` on macOS and `xdg-open` plus
`wl-copy`, `xclip`, or `xsel` on Linux.

The plugin source itself is available under the [MIT License](LICENSE).
