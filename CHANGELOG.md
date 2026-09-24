# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.9.0] — 2026-09-24

### Added
- Claude · Spend page: what your Claude Code tokens would cost at API list prices (today, 7 days, 30 days), top models and projects, cache hit share and a 13-week activity map. Read locally and incrementally from Claude Code's own transcripts in `~/.claude/projects`; only token counts, model, time and project folder are used.
- "Claude finished" notification for turns longer than a chosen time (off, always, 30 s – 5 min; default 1 min), skipped while a terminal is in front.
- The working blob counts up the turn's elapsed time.
- Card size presets: Compact, Spacious (1.25×) and Custom (100–160 %), previewed live.
- Option to hide the badge while an app is full screen; it also hides while the screen is locked or asleep.
- Haptic tap when hover opens the card (Force Touch trackpads, on by default).
- Hairline outline on the open card with Increase Contrast.

### Changed
- The island animates with Core Animation: the silhouette springs open and closed on the render server while the card is laid out once at its final size, and content fades in once the shape is mostly open. Corners grow continuously with the height.
- Hover opens after the delay and closes 0.18 s after leaving, both re-checked against where the card is heading, so edges no longer flicker. A card closed by click or hotkey stays closed until the pointer leaves.
- Even 16 pt margin on the card's sides and bottom; Compact card is 380 pt wide.
- First click on a card button works while another app is in front; our menu bar menu closes the card.

### Fixed
- A card could close right after opening on a fresh launch (a system defaults write was treated as a settings change).
- History: the first row written to a new history file was missing its newline, so the next row merged into it and both were lost.

## [0.8.1] — 2026-09-19

### Added
- App icon and logo: an N with the notch bitten out of its top. Icon ships in the bundle, the same glyph sits in the menu bar (vector, drawn in code) and in the corner of the expanded card.

## [0.8.0] — 2026-09-19

### Added
- Focus tab: Pomodoro timer (15m / 25m / 45m / 1h) with a countdown blob and a notification when it ends.
- Limit blob: red hourglass draining toward the reset while session or weekly usage is at 100 %.
- Clicking a gauge on Overview opens Trends.

### Changed
- Blob icons are smaller.

## [0.7.0] — 2026-09-19

### Added
- Side blobs merge into the notch like liquid (blur + alpha threshold) when the card opens and pop back out on close, with stretch, a reach-out from the notch and a soft bounce.
- Claude Code activity blob: pulsing while a prompt is being answered, green check when done (persists until a terminal app comes to the front or you click it).
- Permission requests are a blob with an expiry ring instead of the Allow/Deny island; hover opens the page. Caffeine and Claude blobs sit on opposite sides ("Caffeine blob on the left" setting).
- Notification when a limit resets after it passed the first threshold (toggle in Settings).

### Changed
- Card width is constant: at least the badge plus blob room, so nothing resizes when a blob appears while the card is open.
- Adapter tracks `busy-`/`done-` markers from UserPromptSubmit/Stop; `SessionEnd` and `Notification` hooks added (re-installed automatically on launch).

### Fixed
- Hovering the caffeine blob flickered the card open and closed.

## [0.6.0] — 2026-09-17

### Added
- Caffeinate shows as a detached side blob with a countdown ring beside the badge (iOS-style); cup removed from the badge.
- Named tab pills (Claude · Caffeinate) with a uniform 12pt layout rhythm.

### Fixed
- Plan approval from the notch now actually applies: `ExitPlanMode` needs `updatedInput` echoed with the allow decision.
- Two-finger swipe and the arrow cursor work while another app is frontmost (global event monitor).
- Expanded card was floored at the island+blob width; now 340pt on every page.
- Caffeinate and Approval pages render before any usage data arrives; hover ignores the transparent strip beside the blob.
- Snappier expand/collapse and button hover; default hover delay 0.15s.

## [0.5.0] — 2026-09-16

### Added
- Plans can be approved from the notch: hover the "Plan ready" island to read the plan and choose Auto-accept edits / Ask on edits / Keep planning (90 s window before the terminal takes over).
- Approval page shows the full command for tool prompts.

### Changed
- Swipe switches between tabs (Claude ↔ Caffeinate); header pills move between a tab's pages.
- Header cup toggle removed; the Caffeinate tab owns it.
- Caffeinate page: big countdown, larger presets, tab icon glows while awake.

### Fixed
- Two-finger swipe did not register (hosting view swallowed scroll events).
- I-beam cursor over the card; now a solid arrow.

## [0.4.0] — 2026-09-16

### Added
- Agent approvals: Claude Code permission prompts show as an Allow/Deny island on the notch, answered through the `PermissionRequest` hook; terminal prompt takes over after 15 s.
- "Plan ready for review" notification when Claude Code presents a plan.
- Card organised into categories: Claude (Overview / Trends / Week pills) and Caffeinate (30m / 1h / 2h / ∞ presets with auto-off, cup indicator in the badge).
- Icon tab bar switches categories; two-finger swipe moves between a category's pages.

### Changed
- Connect Claude Code status line… now also installs the hook entries; existing installs are upgraded on launch.

## [0.2.1] — 2026-09-14

### Fixed
- Badge lagged claude.ai: Claude Code reports cached rate limits and the statusline write overwrote fresh API values. API polling is now authoritative for session/weekly.

## [0.2.0] — 2026-09-14

### Added
- Card corner radius setting with live preview while dragging.
- Badge: countdown-to-reset mode, ring instead of dot.
- Menu bar text mode.
- Per-model weekly buckets (Opus, Sonnet…) on the Overview when the account reports them.
- Configurable alert thresholds and a once-per-window pace warning.
- Global hotkey ⌃⌥N and a pin button to hold the card open.

### Changed
- Roomier expanded card padding.

## [0.1.1] — 2026-09-14

### Added
- Release workflow: tagged builds attach an ad-hoc signed `NotchRate.app` zip.
- Trends page: 5h / 7d charts with burn rate, projection and window usage.
- This week page: per-day bars, sessions, peak, limit hits, CLI cost.
- Local usage history (`~/.notch-usage/history.jsonl`, 8 days).
- Manual refresh button; hover-lit navigation buttons.
- OAuth usage polling so chat and Cowork usage show while the CLI is idle, with token refresh.
- Extra-usage % when pay-as-you-go is enabled.
- Settings: hide badge, show weekly in badge, rings vs bars, poll interval.

### Changed
- Overview header shows "live" while polling is fresh instead of "updated 0m ago".
- Collapsed badge shows session % (was max of session/weekly).
- Overview redesigned around ring gauges.

## [0.1.0] — 2026-09-14

### Added
- Collapsed badge beside the notch, pill on plain displays, follow-mouse.
- Status-line adapter chaining to `ccstatusline`.
- Hover card with session/weekly bars, cost, context.
- Launch at login, notifications at 85 % / 100 %, reduce-motion support.
