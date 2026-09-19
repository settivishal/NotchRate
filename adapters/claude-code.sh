#!/bin/bash
# Claude Code hooks adapter for NotchRate. Modes:
#   (none)      statusLine: dump the JSON to ~/.notch-usage/claude-code.raw (the app parses it),
#               then hand the same JSON to the downstream statusline (default: ccstatusline).
#   permission  PermissionRequest: publish the request to pending/, wait up to
#               NOTCH_APPROVAL_WAIT seconds (NOTCH_PLAN_WAIT for ExitPlanMode) for the app to
#               write an answer, print the decision. Answer grammar: "allow", "allow <mode>"
#               (setMode for the session, e.g. acceptEdits), "deny", or a full JSON decision
#               starting with "{" (the app builds it when updatedInput must be echoed back).
#               No answer in time -> exit silently so the terminal prompt shows as usual.
#   clear       Any later hook: drop this session's pending request (the user answered in the terminal).
#               Also keeps the activity markers: UserPromptSubmit/PreToolUse/PostToolUse touch
#               pending/busy-<id>; Stop swaps it for done-<id> (the app clears that when a terminal
#               comes to the front); SessionEnd removes both; Notification (idle) only removes busy
#               and never touches pending requests.
set -u

OUT_DIR="${NOTCH_USAGE_DIR:-$HOME/.notch-usage}"
DOWNSTREAM="${NOTCH_DOWNSTREAM:-ccstatusline}"
WAIT="${NOTCH_APPROVAL_WAIT:-15}"
PLAN_WAIT="${NOTCH_PLAN_WAIT:-90}"

mkdir -p "$OUT_DIR"

# Top-level string field of the hook payload. Files are keyed by session so parallel sessions never clear each other.
field() { printf '%s' "$2" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" | head -1; }
session_id() { field session_id "$1"; }

case "${1:-}" in
  clear)
    payload=$(cat)
    id=$(session_id "$payload")
    case "$(field hook_event_name "$payload")" in
      UserPromptSubmit|PreToolUse|PostToolUse) mkdir -p "$OUT_DIR/pending"; rm -f "$OUT_DIR/pending/done-${id:-*}"; : > "$OUT_DIR/pending/busy-${id:-$$}" ;;
      Stop) mkdir -p "$OUT_DIR/pending"; rm -f "$OUT_DIR/pending/busy-${id:-*}"; : > "$OUT_DIR/pending/done-${id:-$$}" ;;
      Notification) rm -f "$OUT_DIR/pending/busy-${id:-*}"; exit 0 ;;  # idle prompt: not busy, but the terminal may still be asking
      *) rm -f "$OUT_DIR/pending/busy-${id:-*}" "$OUT_DIR/pending/done-${id:-*}" ;;
    esac
    rm -f "$OUT_DIR/pending/${id:-*}.raw" "$OUT_DIR/pending/plan-${id:-*}.raw"
    exit 0
    ;;
  permission)
    mkdir -p "$OUT_DIR/pending" "$OUT_DIR/answer"
    payload=$(cat)
    id=$(session_id "$payload"); id=${id:-$$}
    # Plans get a longer window (reading time) and a plan- prefix so the app renders them differently.
    case "$payload" in *'"tool_name":"ExitPlanMode"'*|*'"tool_name": "ExitPlanMode"'*)
      id="plan-$id"; WAIT=$PLAN_WAIT ;;
    esac
    trap 'rm -f "$OUT_DIR/pending/$id.raw" "$OUT_DIR/answer/$id"' EXIT
    printf '%s' "$payload" > "$OUT_DIR/pending/$id.raw.tmp" && mv -f "$OUT_DIR/pending/$id.raw.tmp" "$OUT_DIR/pending/$id.raw"
    i=0
    while [ ! -f "$OUT_DIR/answer/$id" ] && [ "$i" -lt "$((WAIT * 4))" ]; do
      sleep 0.25; i=$((i + 1))
    done
    [ -f "$OUT_DIR/answer/$id" ] || exit 0
    read -r verb mode < "$OUT_DIR/answer/$id"
    case "$verb" in
      \{*) cat "$OUT_DIR/answer/$id" ;;
      allow)
        if [ -n "${mode:-}" ]; then
          printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"setMode","mode":"%s","destination":"session"}]}}}' "$mode"
        else
          printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
        fi ;;
      *)
        case "$id" in
          plan-*) msg="User chose to keep planning (from NotchRate)" ;;
          *) msg="Denied from NotchRate" ;;
        esac
        printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"%s"}}}' "$msg" ;;
    esac
    exit 0
    ;;
esac

payload=$(cat)

# Atomic write: the app's directory watcher only ever sees complete files.
printf '%s' "$payload" > "$OUT_DIR/claude-code.raw.tmp" 2>/dev/null && mv -f "$OUT_DIR/claude-code.raw.tmp" "$OUT_DIR/claude-code.raw"

# Never break the terminal statusline, whatever happened above.
if command -v "$DOWNSTREAM" >/dev/null 2>&1; then
  printf '%s' "$payload" | exec "$DOWNSTREAM"
fi
