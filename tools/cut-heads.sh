#!/bin/sh
# Turns every photo in photos/ into a floating sticker-head in heads/, and rewrites heads/heads.js.
# macOS only (it uses Apple's Vision framework). Run it from anywhere:
#
#   sh tools/cut-heads.sh
#
# Then look at photos/_cutouts.png. Per-person fixes go in tools/tunes.json (see AGENTS.md).
set -e
cd "$(dirname "$0")/.."

if [ "$(uname)" != "Darwin" ]; then
  echo "This cutter only runs on a Mac. See 'No Mac?' in AGENTS.md for other ways to make the heads."
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Apple's command line tools are needed first. Run:  xcode-select --install"
  exit 1
fi

BIN="${TMPDIR:-/tmp}/secret-santa-cut-heads"
if [ ! -x "$BIN" ] || [ tools/extract-heads.swift -nt "$BIN" ]; then
  echo "Getting the cutter ready (first run takes about half a minute)..."
  swiftc -O tools/extract-heads.swift -o "$BIN" 2>/dev/null || swiftc -O tools/extract-heads.swift -o "$BIN"
fi
"$BIN" photos heads tools/tunes.json
