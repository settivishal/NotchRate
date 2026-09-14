#!/bin/bash
# Claude Code statusLine adapter for NotchRate.
# Reads statusLine JSON on stdin, writes normalized ~/.notch-usage/claude-code.json,
# then hands the same JSON to the downstream statusline (default: ccstatusline).
set -u

OUT_DIR="${NOTCH_USAGE_DIR:-$HOME/.notch-usage}"
OUT="$OUT_DIR/claude-code.json"
DOWNSTREAM="${NOTCH_DOWNSTREAM:-ccstatusline}"

payload=$(cat)

# Locate jq without relying on PATH (Claude Code may spawn with a minimal env).
JQ=""
for c in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq "$(command -v jq 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { JQ="$c"; break; }
done

if [ -n "$JQ" ]; then
  mkdir -p "$OUT_DIR"
  # Atomic write: watcher only ever sees complete files.
  # Claude Code caches rate_limits and lags the real numbers. If the app's API poller
  # has written this file (source == "api"), keep its session/weekly values.
  prev='{}'; [ -f "$OUT" ] && prev=$(cat "$OUT" 2>/dev/null || echo '{}')
  printf '%s' "$payload" | "$JQ" -c --argjson prev "$prev" '{
    tool: "claude-code",
    session_used_pct: .rate_limits.five_hour.used_percentage,
    session_resets_at: .rate_limits.five_hour.resets_at,
    weekly_used_pct: .rate_limits.seven_day.used_percentage,
    weekly_resets_at: .rate_limits.seven_day.resets_at,
    cost_usd: .cost.total_cost_usd,
    context_pct: .context_window.used_percentage,
    last_updated: now | floor
  } as $new
  | if ($prev.source // "") == "api"
    then $prev + ($new | del(.session_used_pct, .session_resets_at, .weekly_used_pct, .weekly_resets_at))
    else $new end' > "$OUT.tmp" 2>/dev/null && mv -f "$OUT.tmp" "$OUT" || rm -f "$OUT.tmp"
fi

# Never break the terminal statusline, whatever happened above.
if command -v "$DOWNSTREAM" >/dev/null 2>&1; then
  printf '%s' "$payload" | exec "$DOWNSTREAM"
fi
