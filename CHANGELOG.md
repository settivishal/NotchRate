# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
