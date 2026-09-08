#!/bin/sh
# fzf runs previews asynchronously. Share one initialization with the renderer
# instead of loading the full runtime once here and again in render.sh.
set -eu
exec sh "${0%/*}/render.sh" --viewer-preview "$@"
