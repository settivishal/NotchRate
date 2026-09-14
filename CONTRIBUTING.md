# Contributing

Thanks for helping. Keep changes small and focused; one concern per PR.

## Setup

```sh
brew install jq
git clone https://github.com/settivishal/NotchRate.git
cd NotchRate
make run
```

Command Line Tools are enough; see the Makefile for the SDK pin. `make test` runs the Swift tests, `bash adapters/test.sh` the adapter checks.

## Guidelines

- Swift 6, strict concurrency. Keep `@MainActor` on UI-touching types.
- No new dependencies unless there is no reasonable stdlib/AppKit path.
- Idle CPU must stay near zero: no timers for things a DispatchSource or event monitor can do.
- Anything that talks to the network or the Keychain lives in `UsagePoller.swift` and gets a line in the Privacy section of the README.
- Add or update a test when you touch decoding, thresholds, history math or the adapter.
- Commit messages: `feat:`, `fix:`, `docs:`, `chore:` prefixes.

## Adding an adapter

Write `~/.notch-usage/<tool>.json` in the normalized shape from the README (atomic tmp + rename). Put the script under `adapters/`, add a check to `adapters/test.sh`, and document the install step. The app needs no changes.

## Reporting bugs

Use the issue template. Include macOS version, display setup (notch / external), and the contents of `~/.notch-usage/claude-code.json` with any values you consider private removed.
