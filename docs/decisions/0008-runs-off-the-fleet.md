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

## Amendment (2026-11-26)

"Reach a couple of unrelated, reliable targets" was built as a TCP connection
to 1.1.1.1 or 9.9.9.9, by address. On 2026-11-25 Pedant on grab01 ran out of
threads (ADR 0038). Ruby looks a name up in a thread of its own, so no lookup
worked, and 14 monitors named by hostname went down with "Temporary failure
in name resolution". The probe needed no lookup and kept passing, so Pedant's
own failure read as theirs (dkam/pedant#20). A resolver that fails while the
network works would do the same.

**The reference targets are names, `one.one.one.one` and `dns.quad9.net`,
dialled the way a TCP check dials.** Pedant is online only if it can look
one of them up and connect to it. A thread it can't start to try counts as
a failure to connect. While it's offline, a failed check is "unknown: Pedant
is offline, or can't look names up".

- **Rejected: treating some errors as Pedant's, whatever the probe says**
  (`EAI_AGAIN`, `EAGAIN`). A domain whose own nameservers fail also gives
  `EAI_AGAIN`, and that's a real outage. The probe tells the two apart: the
  reference names still resolve when only that domain's fail.
- **Rejected: a second probe, address and name apart,** so a monitor dialled
  by address could still be marked down while only Pedant's lookups fail.
  That's more to build for a rare overlap. While Pedant can't look names up,
  it vouches for nothing.
- **Not done here:** an alert when Pedant itself is degraded but still
  sending its heartbeat, such as a sync failing with `cannot fork()`.
