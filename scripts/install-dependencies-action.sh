#!/bin/sh
# A managed terminal provides interactive approval and package-manager prompts.
set -eu
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-jira-peek}" --entrypoint dependencies \
  --placement split --focus
