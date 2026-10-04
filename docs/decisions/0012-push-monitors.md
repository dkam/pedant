# 0012: Pedant takes over Kuma's push monitors, with Kuma-compatible URLs

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0004 (milestone 1)

## Context

Uptime Kuma does two kinds of monitoring. Pedant must replace both before Kuma
can be retired:

- **Active checks:** Kuma polls a URL or port.
- **Push monitors:** a job calls Kuma when it runs, and silence means it
  didn't. Dan has many of these: backups, host scripts, and other things with
  no URL to poll. Each job ends with a request to
  `/api/push/<token>?status=up&msg=…&ping=…`.

Splat already receives check-ins (Sentry Crons) from the Rails apps' own jobs,
through the Sentry SDK.

## Decision

**Pedant accepts push monitors on Kuma's URL shape:
`/api/push/<token>?status=up|down&msg=…&ping=…`.** Moving a job from Kuma means
changing the hostname in its curl line and nothing else. Kuma's existing tokens
are imported with the monitors (issue #1), so the paths stay the same too.

- `status=down` alerts immediately. Silence past the interval plus grace alerts
  as missed.
- Push monitors use the same liveness model as active checks: up/down, when it
  last changed, and how often it flaps.

**The split with splat:**

- **Splat** keeps check-ins from the Rails apps' own jobs. The SDK sends them
  already; don't move them.
- **Pedant** takes host scripts and anything else that only curls, and shows
  splat's monitor states on its dashboard, so there's one place to look.

## Rules

- **Pedant's own downtime isn't the job's failure.** Pushes sent while Pedant
  was down are lost. After a restart, or a gap in Pedant's own heartbeat, a
  monitor must see one full interval before it can be marked missed.
- **Network.** Pedant is tailnet-only (ADR 0008), so jobs on the tailnet push
  directly. Anything that pushes from outside the tailnet needs a public route
  for `/api/push/*` only. Find out which ones those are from the Kuma export
  before deciding.
- **The token is the credential.** Treat it like one: compare in constant time,
  rate-limit per token, and keep it out of logs (log the monitor's name).
- Kuma accepts the push as GET. Confirm against the export and the real scripts
  whether any use POST, and accept that too if so.

## Alternatives considered

- **Move the push jobs to splat's check-ins.** Rejected: every script would have
  to be rewritten for the Sentry check-in protocol, rather than changing one
  hostname.
- **Leave push monitoring on Kuma.** Rejected: Kuma would never retire, and its
  hand-maintained list is the problem #5 started from.

## Amendment (2026-10-04)

Two decisions were first recorded here and have moved to their own ADRs:
how push monitors were built, including replacing "compare in constant time"
with a digest lookup (ADR 0018), and values, runs and schedules (ADR 0019).
