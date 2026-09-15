#!/bin/bash
# Self-check for claude-code.sh. Run: bash adapters/test.sh
set -eu
cd "$(dirname "$0")"
export NOTCH_USAGE_DIR=$(mktemp -d)
export NOTCH_DOWNSTREAM=cat
OUT="$NOTCH_USAGE_DIR/claude-code.raw"

# Payload lands verbatim in the raw file and is passed through to downstream.
passthrough=$(./claude-code.sh < sample-statusline.json)
[ "$passthrough" = "$(cat sample-statusline.json)" ] || { echo "FAIL passthrough"; exit 1; }
[ "$(cat "$OUT")" = "$(cat sample-statusline.json)" ] || { echo "FAIL raw"; exit 1; }
[ ! -e "$OUT.tmp" ] || { echo "FAIL tmp left"; exit 1; }

rm -rf "$NOTCH_USAGE_DIR"
echo "adapter OK"
