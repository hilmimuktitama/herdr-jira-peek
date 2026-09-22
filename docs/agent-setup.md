# Configure Peek with an AI agent

Give your agent the prompt in the [README](../README.md#ask-your-ai-agent-to-configure-peek)
and describe the work you do. This guide is for the agent carrying out that setup.

## Start with the user's workflow

Use the context already provided. Ask only what is missing:

1. What decision should the picker help you make: choose work, review progress,
   triage urgency, or follow a release?
2. Which two or three facts do you need at a glance, and which belong in the reader?

Keep the summary in the picker unless the user prefers otherwise. Start with
two or three picker fields and a short preview. Put comments and occasional
reference information in the reader. Explain the proposed arrangement in one
sentence; avoid making users configure every available option.

## Find and preserve the existing setup

- Locate the installed plugin and check its `config.example.sh` and manifest.
  Configure only settings supported by that version. Use the README's
  [installation instructions](../README.md#install-and-set-up) if an update or
  first-time installation is needed.
- Run `herdr plugin config-dir jira-peek` to locate the private `config.sh`.
  Do not guess a config path or write personal settings into this repository.
- Read the configuration as data, never source it. Preserve the backend, site,
  project allowlist, credential path, cache settings, and unrelated preferences
  when the request is only about fields.
- For first-time access, use **Set up Peek for Jira** and the documented backend
  instructions. Let the user complete TWG login or enter REST credentials in
  their private netrc file. Do not request, display, or copy credentials into chat.
  Do not read the netrc contents to customize fields.
- Obtain custom field IDs from the user's Jira field settings or an authorized
  field-metadata lookup. Match both name and type; if names are ambiguous, ask
  which one they mean. Never invent an ID or assume a story-points field has the
  same ID on every site. Standard fields are a useful starting point while an
  ID is unknown.

## Apply and validate

1. Close existing Peek viewers and other configuration editors. Make a private
   backup of `config.sh` beside it. Avoid concurrent edits: atomic replacement
   protects readers but does not lock out other writers.
2. Prepare a private candidate with only the requested assignments changed.
   Use one `NAME='value'` per line,
   replace existing assignments rather than appending duplicates, and preserve
   comments and unrelated settings. Keep the directory private (mode `700`)
   and the file mode `600`. Refuse symlinks.
3. Validate field lists locally with the installed `scripts/preferences.sh`
   helpers. Pass the proposed values as arguments or environment variables;
   never execute the user's config as shell code. Do not fetch issues just to
   check field syntax. After validation, check the original has not changed and
   atomically replace it with the candidate.
4. Run **Check Peek for Jira** from Herdr. It validates configuration and checks
   the connection; do not describe offline checks as proof of live connectivity.
   If operating from a shell, use the installed `scripts/doctor.sh` with the
   actual `HERDR_PLUGIN_CONFIG_DIR` and `HERDR_PLUGIN_STATE_DIR` supplied by Herdr.
5. Reopen Peek from a source pane with an allowed issue key. Verify field order,
   readable values, filtering, preview, and Enter → reader → `q` return. Use a
   user-authorized issue for a live check; use fictional fixtures for anything
   saved in this public repository. Confirm a custom field's value is visible
   to the current account rather than guessing why it is empty.
6. Report the chosen fields and any verification still pending in a few lines.
   Keep a recoverable backup; restore it if the new configuration is invalid.

For an interactive alternative, **Customize Peek for Jira** provides presets,
offline previews, and a safe save/cancel flow. Its field prompts accept `?` for
help. Connection setup is separate.

## Field reference

| Setting | Purpose | Default |
| --- | --- | --- |
| `PICKER_FIELDS` | Ordered searchable values after the key | `status,summary` |
| `PREVIEW_FIELDS` | Ordered information in the compact preview | `status,assignee,updated,description,comments` |
| `READER_FIELDS` | Ordered information in the full reader | `status,assignee,updated,link,description,comments` |
| `FIELD_LABELS` | Optional `field:Label` pairs | Empty |

All views accept `status`, `assignee`, `reporter`, `priority`, `issuetype`,
`project`, `created`, `updated`, `duedate`, `resolution`, `labels`, `components`,
`fixVersions`, `versions`, `parent`, and `customfield_` followed by a numeric ID.
The picker also accepts `summary`. Detail views also accept `description`,
`comments`, and `link`; their key and summary are always shown.

Use case-sensitive IDs separated by commas, with no spaces or duplicates.
An empty picker list shows keys only; an empty detail list shows key and summary.
Labels use letters, numbers, spaces, dots, underscores, and hyphens. Use aliases
where they clarify an otherwise ambiguous value, such as a custom field. For
example, `FIELD_LABELS='customfield_10016:Points'` uses a **fictional** field ID.

Colors use the terminal palette; manage the theme and font in Herdr or the
terminal. Optional `TEXT_STYLE='plain'` removes bold and dim emphasis.
`NO_COLOR=1` disables plugin ANSI styling.

Changing the requested fields refreshes incompatible cached issues. Reordering
fields or changing labels reuses compatible entries. Removing `comments` from
both detail lists stops supplemental comment requests. Visibility settings do
not guarantee a backend omits other fields from its response or existing cache;
**Clear Peek for Jira cache** removes cached issue content.

### Starting points

Adapt these to the user's answers; they are starting points, not universal defaults.
These examples need no custom field IDs.

**Implementation work:** recognize the issue quickly and keep discussion in the reader.

```sh
PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status,assignee,description'
READER_FIELDS='status,assignee,description,comments,link'
```

**Triage:** scan urgency first, then inspect ownership and context.

```sh
PICKER_FIELDS='priority,status,summary'
PREVIEW_FIELDS='priority,status,assignee,description'
READER_FIELDS='priority,status,assignee,reporter,updated,description,comments,link'
```

**Release follow-up:** keep versions and deadlines available without crowding the list.

```sh
PICKER_FIELDS='status,summary'
PREVIEW_FIELDS='status,fixVersions,duedate,description'
READER_FIELDS='status,assignee,fixVersions,duedate,description,comments,link'
```
