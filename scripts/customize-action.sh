#!/bin/sh
# Open the offline display-preferences editor in a managed terminal.
set -eu
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-jira-peek}" --entrypoint customize-wizard \
  --placement split --focus
