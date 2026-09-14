#!/bin/bash
# Wire the Claude Code adapter into ~/.claude/settings.json (idempotent).
set -eu
SRC="${1:-$(cd "$(dirname "$0")" && pwd)/adapters/claude-code.sh}"   # optional: path to adapter (used by the curl install)
ADAPTER="$HOME/.notch-usage/bin/claude-code.sh"   # copied out of the repo so moving it does not break the statusline
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "jq missing: brew install jq"; exit 1; }
mkdir -p "$HOME/.notch-usage/bin"
cp "$SRC" "$ADAPTER" && chmod +x "$ADAPTER"

cur=$(jq -r '.statusLine.command // ""' "$SETTINGS")
if [ "$cur" = "$ADAPTER" ]; then echo "adapter updated: $ADAPTER"; exit 0; fi
# Keep whatever was there as the downstream statusline (default ccstatusline).
[ -n "$cur" ] && [ "$cur" != "ccstatusline" ] && [ "${cur##*/}" != "claude-code.sh" ] && echo "note: previous statusLine was '$cur'; adapter chains to ccstatusline (NOTCH_DOWNSTREAM to change)."

cp "$SETTINGS" "$SETTINGS.bak"
jq --arg cmd "$ADAPTER" '.statusLine = ((.statusLine // {}) + {type:"command", command:$cmd})' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "installed: $ADAPTER (backup at $SETTINGS.bak). Restart Claude Code."
