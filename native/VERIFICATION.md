# Native highlighting verification

Verified locally on macOS arm64 with Herdr 0.9.1 and Zed 1.21.0.
All fixtures used fictional issue data.

## Renderer and integration

- Full plugin runtime suite: passed, including both real fzf PTY layouts,
  resize/filter/reader/rescan checks, multiple source panes and auth lifecycle.
- ShellCheck, shell syntax, Python compilation and manifest checks: passed.
- Full upstream process-isolated suite: 3,463 passed, 6 skipped.
- Final native renderer tests: 5 passed, including real Ghostty normal and
  alternate buffers, exact-token boundaries, Unicode positions and soft wraps.
- Upstream architecture checks: 6 passed.
- Clippy, all targets with warnings denied: passed.
- Worker: 12 tests passed. Socket client: 8 tests passed. Worker subprocess
  integration: passed. Highlight UI checks: passed.
- Installed release PTY test: passed. It checks actual emitted ANSI cell colors
  in a terminal emulator, selected-key changes, alternate-screen redraws,
  direct terminal attachment, cleanup, lease expiration, and owner/identity guards.
- Patch application checked against the pinned clean upstream commit.

## Visual checks

Computer Use verified amber highlights in Zed's original source pane with
fictional fixture output, a real OpenCode conversation, and the real Claude Code
UI. Changing Peek selection moved the highlight; closing Peek restored the
source styles. Claude Code's login had expired, so a new generated Claude reply
could not be tested. Its displayed prompt and live UI were tested.

## Handoff

A stock Homebrew-to-native release handoff passed in an isolated session,
preserving the original terminal process PID. A native release-to-release
handoff retained the running Claude process and Peek's
terminal process. The native API was available afterward. Herdr clients must
reconnect, and Peek must reopen because upstream handoff recreates terminal
handles. A debug-to-release experiment exposed different socket paths; the
activation helper now rejects the standard debug-session path.

## Rendering cost

The added release benchmark rendered populated 80 × 24 terminals for 100
frames. Times below are local measurements, not performance guarantees.

| Panes | No highlight | Highlight enabled |
| --- | ---: | ---: |
| 1 | 264.75 µs/frame | 318.95 µs/frame |
| 15 | 4,187.13 µs/frame | 5,521.37 µs/frame |

The six existing upstream render-scale profiles also passed. The highlighted
benchmark deliberately decorates every pane; an ordinary Peek session decorates
one source terminal.
