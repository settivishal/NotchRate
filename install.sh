#!/bin/bash
# Wire the Claude Code adapter into ~/.claude/settings.json (idempotent).
set -eu
ADAPTER="$(cd "$(dirname "$0")" && pwd)/adapters/claude-code.sh"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "jq missing: brew install jq"; exit 1; }
mkdir -p "$HOME/.notch-usage"

cur=$(jq -r '.statusLine.command // ""' "$SETTINGS")
if [ "$cur" = "$ADAPTER" ]; then echo "already installed"; exit 0; fi
# Keep whatever was there as the downstream statusline (default ccstatusline).
[ -n "$cur" ] && [ "$cur" != "ccstatusline" ] && echo "note: previous statusLine was '$cur'; adapter chains to ccstatusline. Set NOTCH_DOWNSTREAM in adapters/claude-code.sh to change."

cp "$SETTINGS" "$SETTINGS.bak"
jq --arg cmd "$ADAPTER" '.statusLine = ((.statusLine // {}) + {type:"command", command:$cmd})' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "installed: $ADAPTER (backup at $SETTINGS.bak). Restart Claude Code."
