#!/bin/bash
# Self-check for claude-code.sh. Run: bash adapters/test.sh
set -eu
cd "$(dirname "$0")"
export NOTCH_USAGE_DIR=$(mktemp -d)
export NOTCH_DOWNSTREAM=cat
export NOTCH_APPROVAL_WAIT=2
OUT="$NOTCH_USAGE_DIR/claude-code.raw"

# Payload lands verbatim in the raw file and is passed through to downstream.
passthrough=$(./claude-code.sh < sample-statusline.json)
[ "$passthrough" = "$(cat sample-statusline.json)" ] || { echo "FAIL passthrough"; exit 1; }
[ "$(cat "$OUT")" = "$(cat sample-statusline.json)" ] || { echo "FAIL raw"; exit 1; }
[ ! -e "$OUT.tmp" ] || { echo "FAIL tmp left"; exit 1; }

req='{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

# Answered from the app: decision printed, pending/answer cleaned up.
( sleep 0.5; [ -f "$NOTCH_USAGE_DIR/pending/s1.raw" ] && echo allow > "$NOTCH_USAGE_DIR/answer/s1" ) &
out=$(printf '%s' "$req" | ./claude-code.sh permission)
wait
[[ "$out" == *'"behavior":"allow"'* ]] || { echo "FAIL allow: $out"; exit 1; }
[ -z "$(ls "$NOTCH_USAGE_DIR/pending")" ] || { echo "FAIL pending left"; exit 1; }
[ -z "$(ls "$NOTCH_USAGE_DIR/answer")" ] || { echo "FAIL answer left"; exit 1; }

# Timeout: silent exit, terminal prompt takes over.
out=$(printf '%s' "$req" | ./claude-code.sh permission)
[ -z "$out" ] || { echo "FAIL timeout output: $out"; exit 1; }
[ -z "$(ls "$NOTCH_USAGE_DIR/pending")" ] || { echo "FAIL pending left after timeout"; exit 1; }

# Plan approval: file for the app, no decision, no wait.
out=$(printf '%s' '{"session_id":"s1","tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}' | ./claude-code.sh permission)
[ -z "$out" ] || { echo "FAIL plan output"; exit 1; }
[ -f "$NOTCH_USAGE_DIR/pending/plan-s1.raw" ] || { echo "FAIL plan file"; exit 1; }
# clear only touches its own session.
printf '%s' '{"session_id":"s2"}' | ./claude-code.sh clear
[ -f "$NOTCH_USAGE_DIR/pending/plan-s1.raw" ] || { echo "FAIL cleared other session"; exit 1; }
printf '%s' '{"session_id":"s1"}' | ./claude-code.sh clear
[ -z "$(ls "$NOTCH_USAGE_DIR/pending")" ] || { echo "FAIL clear"; exit 1; }

rm -rf "$NOTCH_USAGE_DIR"
echo "adapter OK"
