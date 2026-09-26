#!/bin/sh
# Build an opt-in local Herdr variant; never replace a package-manager binary.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
REVISION=065ef9d6a531c49fb8bee7e818ef837065b21ee9
build_root=${1:-"$ROOT/.local/herdr-native-source"}
for dependency in git cargo zig; do
  command -v "$dependency" >/dev/null 2>&1 || { printf '%s is required\n' "$dependency" >&2; exit 1; }
done
[ "$(zig version)" = 0.16.0 ] || { printf 'Zig 0.16.0 is required\n' >&2; exit 1; }
[ ! -e "$build_root" ] || { printf 'Choose a new, nonexistent build directory: %s\n' "$build_root" >&2; exit 1; }
git clone --depth 1 --branch v0.9.1 https://github.com/herdrdev/herdr.git "$build_root"
[ "$(git -C "$build_root" rev-parse HEAD)" = "$REVISION" ] || { printf 'Unexpected upstream revision\n' >&2; exit 1; }
git -C "$build_root" apply --check "$ROOT/native/herdr-0.9.1-highlight.patch"
git -C "$build_root" apply "$ROOT/native/herdr-0.9.1-highlight.patch"
(cd "$build_root" && cargo build --release --locked)
mkdir -p "$ROOT/.local/bin"
install -m 755 "$build_root/target/release/herdr" "$ROOT/.local/bin/herdr-peek.new"
mv "$ROOT/.local/bin/herdr-peek.new" "$ROOT/.local/bin/herdr-peek"
printf 'Built %s\nSee native/README.md for activation.\n' "$ROOT/.local/bin/herdr-peek"
