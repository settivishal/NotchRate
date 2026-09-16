# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
