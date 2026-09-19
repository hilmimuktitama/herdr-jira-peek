#!/bin/sh
# Open the managed terminal used by the connection wizard.
set -eu
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-jira-peek}" --entrypoint setup-wizard \
  --placement split --focus
