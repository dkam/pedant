# 0008: Pedant runs off the fleet, on the tailnet

**Date:** 2026-10-04
**Status:** Accepted. Which host is deliberately not decided, because nothing in
the code depends on it. Proxmox at home and grab01 in Melbourne are both
candidates.

## Context

Pedant watches hetz01 and misc01. If it ran on either, an outage on that host
would take down the thing meant to report it. Kuma has that problem today: it
runs on misc01.

## Decision

**Pedant runs on a host it doesn't manage, and is reachable on the tailnet
only.** Any host will do if it:

- is on the tailnet, so Pedant can reach the hosts, and Gitea (on hetz01) can
  deliver webhooks to Pedant (ADR 0002; polling the forge is the fallback)
- has outbound HTTPS for the uptime checks
- can pull `ghcr.io/dkam/pedant`.

## Consequences for the code, whatever the host

- **Pedant's own connection failing must not read as everything going down.**
  Before marking a service down, confirm Pedant can reach a couple of
  unrelated, reliable targets. If it can't, record "unknown, Pedant is
  offline", not an outage.
- **Someone has to watch Pedant.** If Pedant's host goes down, every alert goes
  quiet. Pedant sends a regular heartbeat to something on the fleet, so silence
  raises an alarm. Splat's cron monitors (on hetz01) are the obvious candidate.
- Uptime is measured from wherever Pedant sits, so it's one vantage point,
  not a global view. That's fine for replacing Kuma, which has the same limit.

## Open

- How alerts are delivered. Kuma's current notification channels should be
  part of the Kuma export.
