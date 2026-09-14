# NotchRate

Your Claude Code rate-limit usage, in the MacBook notch.

A tiny native macOS app that shows how much of your Claude Code session (5-hour) and weekly (7-day) limits you've used, right beside the notch. Glance at it; hover it for detail. Near-zero idle CPU.

## What you see

**Collapsed** — a colored dot and the highest of your two percentages, sitting in black wings that merge with the notch. On a display without a notch (external monitor), the same badge as a small pill at the top-center of the menu bar.

- Green under 60%, yellow 60–85%, red above 85%
- Greyed out if Claude Code hasn't reported anything for 2 hours (configurable)

**Hover** (0.3s) — expands to show:

- Session usage with a bar and reset countdown
- Weekly usage with a bar and reset countdown
- Session cost in USD
- Context window usage

Click the badge to open your usage page on claude.ai. The badge follows your mouse across displays, or can be pinned to the notch screen only. You get a notification when session or weekly usage crosses 85% and 100%.

## How it works

While Claude Code is idle the app also polls Anthropic's OAuth usage endpoint every 60s (using Claude Code's own Keychain token), so usage from claude.ai chat and Cowork — which share the same Pro/Max limits — shows up too.

Claude Code runs a [status line](https://code.claude.com/docs/en/statusline) script after every turn and pipes it JSON including `rate_limits`, `cost` and `context_window`. NotchRate installs a small wrapper as that script:

```
adapters/claude-code.sh
  stdin JSON ──▶ ~/.notch-usage/claude-code.json   (normalized, atomic write)
             └─▶ ccstatusline                      (your existing status line, unchanged)
```

The app watches `~/.notch-usage/` with a filesystem event source (no polling) and re-renders when the file changes. Adapters for other tools would write their own `<tool>.json` in the same normalized shape; the app never reads tool-specific JSON.

```json
{
  "tool": "claude-code",
  "session_used_pct": 42, "session_resets_at": 1757900000,
  "weekly_used_pct": 18,  "weekly_resets_at": 1758200000,
  "cost_usd": 1.23, "context_pct": 37,
  "last_updated": 1757850000
}
```

## Install

Requirements: macOS 26+, Apple Silicon, Claude Code with a Pro/Max subscription (rate limits are only reported for those), `jq` (`brew install jq`), Xcode Command Line Tools.

```sh
git clone https://github.com/settivishal/NotchRate.git
cd NotchRate
make install
```

This builds the app into `/Applications/NotchRate.app`, copies the adapter to `~/.notch-usage/bin/`, and points `~/.claude/settings.json`'s `statusLine` at it (a backup is saved as `settings.json.bak`). Restart Claude Code; the badge appears after the first response.

If you were using a status line other than `ccstatusline`, set `NOTCH_DOWNSTREAM` at the top of the adapter to chain to it instead.

## Settings

From the menu bar gauge icon → Settings…

- Launch at login
- Follow mouse to every display, or notch screen only
- Hover delay
- Badge width beside the notch
- Hours without updates before the badge dims

## Development

```sh
make run     # build to build/NotchRate.app and launch
make test    # swift-testing unit tests
bash adapters/test.sh   # adapter self-check
```

Builds with Command Line Tools alone (no Xcode). The Makefile pins the macOS 26.5 SDK because the 27 SDK's SwiftUI macros need a plugin that only ships with Xcode. Xcode can open `Package.swift` directly if you have it.

Source layout:

| File | Role |
|---|---|
| `adapters/claude-code.sh` | statusLine wrapper, writes normalized JSON |
| `NotchRate/UsageStore.swift` | watches `~/.notch-usage`, decodes snapshots |
| `NotchRate/NotchGeometry.swift` | per-screen notch/pill sizing |
| `NotchRate/NotchView.swift` | collapsed badge and expanded detail |
| `NotchRate/ScreenTracker.swift` | which display hosts the badge |
| `NotchRate/Notifier.swift` | 85% / 100% notifications |

## Not yet

- Codex CLI, Cursor, Copilot adapters
- Usage history or graphs
- Signed/notarized builds

## License

MIT
