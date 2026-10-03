# 0004: Milestone 1 works without doco-cd

**Date:** 2026-10-04
**Status:** Proposed. Awaiting Dan's confirmation.

## Context

ADRs 0001 and 0002 describe Pedant as a reader of doco-cd's API. doco-cd isn't
installed on any host, and the misc01 trial hasn't started. Building against
its API now would mean writing code that can't be run.

## Decision

Milestone 1 is the two parts of Pedant that are useful today:

1. **Uptime checks: the Kuma replacement.**
   - HTTP checks on a schedule, recording up/down, when that last changed, and
     how often it flaps (rubberneck's liveness model, per #5).
   - Seeded from Kuma's current monitor list, which hasn't been exported yet
     (the first step in #5).
2. **Fleet inventory over SSH.**
   - Per host, `docker ps` and `docker inspect` give the container, image, tag
     and the `org.opencontainers.image.version` / `.revision` labels. This is
     #5's `bin/fleet` folded into the app.
   - Hosts are declared by hand (hetz01, misc01).
   - Read-only commands only.

The source of "what's running" sits behind one interface, so a doco-cd reader
can replace or sit beside the SSH reader later without changing the views.

## Consequences

- Kuma can be retired at the end of milestone 1, without waiting on doco-cd.
- The SSH reader may outlive the trial. If doco-cd's project endpoint doesn't
  return image labels (an open question in ADR 0001), Pedant needs `docker
  inspect` anyway.
- Drift, PR previews and deploy triggering wait until there is real doco-cd
  state to read.
