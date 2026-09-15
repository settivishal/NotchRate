#!/bin/bash
# Claude Code statusLine adapter for NotchRate.
# Dumps the statusLine JSON to ~/.notch-usage/claude-code.raw (the app parses it),
# then hands the same JSON to the downstream statusline (default: ccstatusline).
set -u

OUT_DIR="${NOTCH_USAGE_DIR:-$HOME/.notch-usage}"
DOWNSTREAM="${NOTCH_DOWNSTREAM:-ccstatusline}"

payload=$(cat)

# Atomic write: the app's directory watcher only ever sees complete files.
mkdir -p "$OUT_DIR"
printf '%s' "$payload" > "$OUT_DIR/claude-code.raw.tmp" 2>/dev/null && mv -f "$OUT_DIR/claude-code.raw.tmp" "$OUT_DIR/claude-code.raw"

# Never break the terminal statusline, whatever happened above.
if command -v "$DOWNSTREAM" >/dev/null 2>&1; then
  printf '%s' "$payload" | exec "$DOWNSTREAM"
fi
