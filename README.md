# Peek for Jira

Read Jira Cloud issues without leaving [Herdr](https://herdr.dev/).
Invoke Peek from a terminal containing issue keys. Browse the matching issues
and read descriptions and comments in an adjacent pane.

![Peek beside a source terminal, with an issue list and preview. All data is fictional.](docs/screenshots/workflow-bottom.png)

[Install](#install-and-set-up) · [Controls](#controls) ·
[Configure](#configure) · [Troubleshooting](#troubleshooting)

## Install and set up

Requires [Herdr](https://herdr.dev/docs/install/) >= 0.8.2 on macOS or Linux,
`git`, `fzf`, `jq`, and `less`. Use the official
[TWG CLI](https://developer.atlassian.com/cloud/twg-cli/getting-started/installation/)
1.2.6 or newer with OAuth (the default), or Jira Cloud REST with `curl` and an API token.

Install [v0.4.2](https://github.com/hilmimuktitama/herdr-jira-peek/releases/tag/v0.4.2),
pinned to its release commit:

```sh
herdr plugin install hilmimuktitama/herdr-jira-peek --ref 4bf4b69f56ff1c0a40cc3198f7b187d3f3de08cf
```

1. Select **Set up Peek for Jira** from Herdr's plugin actions. Choose your
   backend, Jira site, and allowed projects.
2. If tools are missing, select **Install Peek for Jira dependencies** and
   approve the installations you want.
3. For TWG, run `twg setup` to sign in. For REST, follow
   [REST authentication](#rest-authentication). Rerun **Set up Peek for Jira**
   after resolving missing tools or authentication. Setup saves only after
   validation succeeds; cancellation or failure preserves your configuration.
4. Focus a terminal containing an allowed issue key and select
   **Peek for Jira issue from pane**.

### Keybinding

Add this to `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+i"
type = "plugin_action"
command = "jira-peek.peek"
```

Then reload Herdr's configuration:

```sh
herdr server reload-config
```

With Herdr's default prefix, press **Ctrl-B**, release it, then press **i**.
Installation does not add this binding automatically.
Other action IDs are listed in the [plugin manifest](herdr-plugin.toml).

## Using Peek

Peek scans the focused terminal for keys in your project allowlist. Recent
issues appear nearest the filter at the bottom. Type to filter by key or
shown fields, use the arrows to select an issue, and press **Enter** for the
full reader. Press **q** to return or **Esc** to close Peek.

Each source terminal keeps its own viewer. Invoke Peek again from the same
source to close its viewer. **Ctrl-G** picks up new keys from that source;
**Ctrl-R** fetches fresh data for the selected issue.

When Herdr recognizes a full-screen agent, Peek scans passive snapshots so it
does not scroll the agent's transcript. Bring an older key into view before
pressing Ctrl-G if it does not appear in the issue list.

The preview adapts to the pane size and hides when space is too limited.
Choose a top-aligned layout or different fields in [configuration](#configure).

## Controls

| Key | Action |
| --- | --- |
| Up / Down | Select an issue |
| Type | Filter by key or displayed fields |
| Ctrl-U | Clear the filter |
| Enter | Open the full reader; `q` returns to the picker |
| Shift-Up / Shift-Down | Scroll the preview in small steps |
| PgUp / PgDn | Page through the preview |
| Ctrl-D | Scroll the preview down half a page |
| Ctrl-O | Open the issue in your browser |
| Ctrl-Y / Ctrl-L | Copy the issue key / link |
| Ctrl-G | Rescan the source terminal |
| Ctrl-R | Refresh the selected issue |
| F1 | Show or hide shortcut help |
| Esc | Close Peek |

In the reader, use arrows to scroll and **Space** / **b** for the next / previous
page. On a MacBook, **Fn-Up** / **Fn-Down** work as PgUp / PgDn.

## Configure

Use **Set up Peek for Jira** for connection settings and **Customize Peek for
Jira** for fields. To edit settings directly, locate your private `config.sh`:

```sh
herdr plugin config-dir jira-peek
```

Common settings:

```sh
JIRA_BASE='https://your-site.atlassian.net'
JIRA_BACKEND='twg'
JIRA_SITE='your-site'
JIRA_PROJECTS='ABC|DEF'
PICKER_LAYOUT='bottom'
CACHE_TTL_MIN=10
MAX_CANDIDATES=20
SOURCE_HIGHLIGHT='off'
```

- `JIRA_BASE` is your site's HTTPS origin, without a trailing slash or path.
- `JIRA_PROJECTS` lists allowed project prefixes, separated by `|`.
- `PICKER_LAYOUT='bottom'` places recent issues near the bottom with the preview
  above. Use `top` for a top-aligned list and a side preview in wide panes.
- `CACHE_TTL_MIN=0` disables durable issue caching. **Clear Peek for Jira cache**
  removes cached issues; see [retention and cleanup](SECURITY.md#local-data-cleanup)
  for other local state.
- `MAX_CANDIDATES` sets how many issues preload metadata (1–100). All detected
  keys remain searchable; older issues load when selected.
- `SOURCE_HIGHLIGHT='auto'` enables native amber highlighting of the selected
  key in the original terminal. Requires Python 3.9+ and the
  [patched Herdr build](native/README.md); stock Herdr 0.9.1 has no native
  decoration API. It is off by default. Reopen Peek after changing the setting.

See [config.example.sh](config.example.sh) for all settings. Use one literal
`NAME=value` assignment per line; keep credentials outside this file. Close
viewers before changing configuration, then run **Check Peek for Jira** and
reopen Peek.

Herdr matches and styles the actual rendered text cells on every redraw. This
works in Zed's embedded terminal, including OpenCode and Claude Code, without
Kitty graphics. Markers follow selection changes, terminal output, scrolling,
resizing, and normal/alternate screen changes. Matching respects token boundaries,
Unicode cell widths, and terminal soft wraps. Application-inserted hard line breaks
remain separate: a key split by the application's own layout is not joined.

Peek never sends input, changes focus, or scrolls the source to make a key visible.
The decoration follows the original terminal identity when a pane moves. Closing
Peek clears it; if Peek crashes or loses its connection, Herdr removes it after
1.5 seconds without renewal. Successful highlighting adds no status text or extra
row; keys outside the visible viewport stay unmarked.
Older Herdr builds show `Source: native highlight requires Herdr update`.

### Choose your fields

**Customize Peek for Jira** offers presets and an offline preview using
fictional data. Choose fields, save, and reopen Peek. Colors follow your
terminal palette.

Or set the order yourself in `config.sh`:

```sh
PICKER_FIELDS='priority,status,summary'
PREVIEW_FIELDS='status,assignee,description'
READER_FIELDS='status,reporter,duedate,description,comments,link'
```

The issue key stays visible; detail views also retain the summary. For custom
fields, labels, workflow examples, or help from an AI agent, see the
[agent setup guide and field reference](docs/agent-setup.md).

### REST authentication

<details>
<summary>Use a Jira API token instead of TWG OAuth</summary>

Choose `rest` during setup, then provide the netrc path and cloud ID described
below. For an existing setup, the corresponding `config.sh` settings are:

```sh
JIRA_BACKEND='rest'
JIRA_NETRC_FILE='/absolute/path/to/jira-peek.netrc'
# Set this for a scoped API token; leave empty for an unscoped token.
JIRA_CLOUD_ID='your-cloud-id'
```

Create the netrc file outside the repository with permissions `600` (or `400`).
Use your editor to enter your account email and API token. For a scoped token,
use this format with your own credentials:

```text
machine api.atlassian.com
login reader@example.test
password REPLACE_WITH_API_TOKEN
```

For an unscoped token, leave `JIRA_CLOUD_ID` empty and use the hostname from
`JIRA_BASE` as the netrc `machine`, without `https://` or a path. Use an
absolute file path in `JIRA_NETRC_FILE`; `~` and `$HOME` are not expanded.

See Atlassian's [API token instructions](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/)
for tokens and cloud IDs. Classic scopes require `read:jira-work` for issues
and `read:jira-user` for the connection check; for granular scopes, follow the
[REST API reference](https://developer.atlassian.com/cloud/jira/platform/rest/v3/).

Run **Check Peek for Jira** to validate access. REST uses the same picker and
controls and never falls back to TWG.

</details>

## Update or remove

Close Peek viewers, then rerun the pinned install command above to update a
GitHub-managed installation. For a linked local checkout, update that checkout
directly; see [local development](CONTRIBUTING.md#local-development).

Remove a GitHub-managed installation with:

```sh
herdr plugin uninstall jira-peek
```

For a linked checkout, use `herdr plugin unlink jira-peek`. See
[local data cleanup](SECURITY.md#local-data-cleanup) to remove retained state.

## Troubleshooting

Start with **Check Peek for Jira** in Herdr's plugin actions. It checks
configuration, dependencies, and Jira access.

- **Missing tools:** run **Install Peek for Jira dependencies** and ensure the
  tools are on Herdr's `PATH`.
- **Authentication fails:** run `twg setup` for TWG, or check the absolute netrc
  path and private file permissions for REST. Confirm the configured site and
  your account's access, then rerun the check.
- **No issues found:** focus a terminal containing a Jira key whose project is
  in `JIRA_PROJECTS`. A custom `KEY_RE` must match it too.
- **Source highlight is missing:** confirm `SOURCE_HIGHLIGHT='auto'`, Python
  3.9+, and the [native Herdr patch](native/README.md), then reopen Peek. The
  running server must support `pane.highlight.set`; updating only the plugin
  cannot add that capability. Only visible, complete keys or terminal-soft-wrapped
  keys are marked.
- **Numbered recovery menu:** fzf failed to start. Review the displayed
  diagnostic and upgrade fzf; the menu shows its own controls.
- **Shortcut does nothing:** check for a conflicting binding, confirm the
  action is `jira-peek.peek`, and run `herdr server reload-config`.
- **Browser or copy fails:** macOS uses `open` and `pbcopy`; Linux needs
  `xdg-open` and one of `wl-copy`, `xclip`, or `xsel` on `PATH`.

## Privacy and project information

Peek is read-only. It temporarily captures the source pane locally to find
keys and sends only validated keys to Jira. Issue content, selected keys, and
bookkeeping can remain in private local state. See the [security policy](SECURITY.md)
for retention, cleanup, and reporting vulnerabilities.

Unofficial community plugin, unaffiliated with Atlassian.
[MIT license](LICENSE) · [Contributing](CONTRIBUTING.md) ·
[Changelog](CHANGELOG.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
