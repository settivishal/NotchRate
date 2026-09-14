#!/bin/bash
# Self-check for claude-code.sh. Run: bash adapters/test.sh
set -eu
cd "$(dirname "$0")"
export NOTCH_USAGE_DIR=$(mktemp -d)
export NOTCH_DOWNSTREAM=cat
OUT="$NOTCH_USAGE_DIR/claude-code.json"

# 1. Full payload -> all fields, and stdin passed through to downstream.
passthrough=$(./claude-code.sh < sample-statusline.json)
[ "$(printf '%s' "$passthrough" | jq -r .version)" = "2.1.90" ] || { echo "FAIL passthrough"; exit 1; }
jq -e '.tool=="claude-code" and .session_used_pct==42.5 and .session_resets_at==1757900000
       and .weekly_used_pct==18 and .cost_usd==1.23 and .context_pct==37
       and (.last_updated|type)=="number"' "$OUT" >/dev/null || { echo "FAIL fields"; cat "$OUT"; exit 1; }

# 2. No rate_limits (pre-first-response / API key user) -> nulls, still writes.
echo '{"cost":{"total_cost_usd":0}}' | ./claude-code.sh >/dev/null
jq -e '.session_used_pct==null and .cost_usd==0' "$OUT" >/dev/null || { echo "FAIL nulls"; exit 1; }

# 3. Garbage stdin -> previous file untouched, exit 0.
before=$(cat "$OUT")
echo 'not json' | ./claude-code.sh >/dev/null
[ "$(cat "$OUT")" = "$before" ] || { echo "FAIL garbage overwrote"; exit 1; }
[ ! -e "$OUT.tmp" ] || { echo "FAIL tmp left"; exit 1; }

# 4. API poller owns the file (source=api) -> statusline keeps its session/weekly, updates cost.
echo '{"tool":"claude-code","source":"api","session_used_pct":51,"weekly_used_pct":20,"cost_usd":0}' > "$OUT"
./claude-code.sh < sample-statusline.json >/dev/null
jq -e '.source=="api" and .session_used_pct==51 and .weekly_used_pct==20 and .cost_usd==1.23 and .context_pct==37' "$OUT" >/dev/null || { echo "FAIL api precedence"; cat "$OUT"; exit 1; }

rm -rf "$NOTCH_USAGE_DIR"
echo "adapter OK"
