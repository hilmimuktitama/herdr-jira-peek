# Native source highlighting

Stock Herdr 0.9.1 accepts image overlays, but Zed does not render that image
protocol. This local patch adds text decorations to Herdr's rendered cells.
The original PTY and agent processes receive no injected text or escape codes.

The patch is pinned to Herdr v0.9.1, commit
`065ef9d6a531c49fb8bee7e818ef837065b21ee9`. It is a local variant, not an upstream
release. It changes no persisted state or existing client/endpoint wire fields.
Existing clients can display the resulting ANSI colors.

## Build

Install Rust (the upstream toolchain file selects the version), Zig 0.16.0,
and the platform build tools required by Herdr, then run:

```sh
sh native/build-herdr.sh
```

This checks the upstream revision and applies the reviewed patch, builds with
`Cargo.lock`, and writes `.local/bin/herdr-peek`. It does not overwrite Homebrew
or any other installed binary. `.local/` is ignored by Git.

## Activate

The running **server**, not just the command on PATH, needs the patch. Close
Peek before switching, then reopen it after the server is upgraded. Enable
`SOURCE_HIGHLIGHT='auto'` in your local plugin config.

For a new session, launch `.local/bin/herdr-peek` after the previous server has
stopped. For an existing session, Herdr's `server.live_handoff` API can replace
the server while preserving PTYs and running processes. Attached clients
disconnect and must reconnect by running Herdr again. Run `activate.py` from
a shell **inside the intended Herdr session**:

```sh
python3 native/activate.py "$PWD/.local/bin/herdr-peek"
```

The helper validates protocol 22 and version 0.9.1 before invoking handoff and
checks that the native API is available afterward. To revert, use the same helper
with `--rollback` and the absolute path to the original Herdr 0.9.1 binary.
Use release-to-release handoff only: debug builds use different socket paths.
Upstream handoff recreates terminal handles while preserving the processes;
reopening Peek binds it to the new handle.
A future package-manager update may replace the running server with a stock
build; Peek then reports that the native highlight API is missing.

## Contract

`pane.highlight.set` accepts `pane_id`, the expected `terminal_id`, a unique
`owner` string, and a literal ASCII token `query` (1–128 bytes). It returns `ok`
and leases the decoration for 1500 ms. Renewing the same query extends its life
without forcing a new frame. A different live owner is rejected. There are at
most 64 active leases. `pane.highlight.clear` accepts `terminal_id` and `owner`;
it cannot remove another owner's lease. Peek uses a fresh random owner per run.

Matching uses rendered cell symbols and actual terminal soft-wrap metadata
under the terminal lock. It preserves text, links, cursor positions, and source
content. Normal and alternate buffers use the same path. Application-inserted
hard line breaks are not joined. Hidden terminal text stays hidden.

The retained dirty-row optimization falls back to a full frame only when a dirty
terminal has an active decoration. Lease expiration forces a redraw even if the
source has stopped producing output. Source pane moves retain the stable terminal
identity; replaced terminals fail the expected-identity check.

## Verification

Run the plugin suite plus `tests/highlight-worker.py`,
`tests/highlight-integration.py`, and `tests/highlight-ui.sh`. With `pyte` installed:

```sh
HERDR_NATIVE_TEST_BIN="$PWD/.local/bin/herdr-peek" python3 tests/highlight-live.py
```

The patch includes Rust tests for exact tokens, Unicode cell positions, soft-wrap
boundaries, and lease expiry. Run upstream `cargo nextest run --locked` (process
isolation is required by upstream tests), `cargo clippy --all-targets --locked --
-D warnings`, and the `just bench-render-scale` recipe. Use fictional fixtures for
visual verification in Zed, OpenCode, and Claude Code; never publish live work data.
