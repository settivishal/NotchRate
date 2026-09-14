# Security

## What NotchRate touches

| Surface | Detail |
|---|---|
| Network | `GET https://api.anthropic.com/api/oauth/usage` on the poll interval; `POST https://console.anthropic.com/v1/oauth/token` only when the access token has expired. No other hosts. |
| Keychain | Reads the `Claude Code-credentials` generic-password item through `/usr/bin/security`. Writes it back only after a token refresh, keeping all other fields intact. |
| Disk | `~/.notch-usage/` (snapshot JSON, history log, adapter script) and `~/.claude/settings.json` (`statusLine.command` only; a `.bak` is kept). |
| Processes | Spawns `/usr/bin/security` and, via the adapter, `jq` and your downstream status line. |

There is no telemetry, no analytics, no crash reporting.

## Reporting a vulnerability

Open a [private security advisory](https://github.com/settivishal/NotchRate/security/advisories/new) or email the maintainer listed on the GitHub profile. Please do not file public issues for anything involving credentials. You will get a response within a week.
