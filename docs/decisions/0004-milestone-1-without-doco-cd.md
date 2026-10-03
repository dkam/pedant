# 0004: Milestone 1 is uptime checks, without doco-cd

**Date:** 2026-10-04
**Status:** Accepted 2026-10-04. Uptime checks are confirmed; the SSH inventory
is undecided.

## Context

ADRs 0001 and 0002 describe Pedant as a reader of doco-cd's API. doco-cd isn't
installed on any host, and the misc01 trial hasn't started. Building against
its API now would mean writing code that can't be run.

## Decision

**Milestone 1 is uptime checks, replacing Uptime Kuma.**

- HTTP checks on a schedule, recording up/down, when that last changed, and how
  often it flaps (rubberneck's liveness model, per #5).
- Seeded from Kuma's current monitor list, which hasn't been exported yet (the
  first step in #5).
- Kuma is retired once Pedant covers its monitors.

**The fleet inventory over SSH is optional, and undecided.** It would be #5's
`bin/fleet` folded into the app: per host, `docker ps` and field-selected
`docker inspect` (never `.Config.Env`; see ADR 0007), giving container, image,
tag and version labels. Hosts would be declared by hand (hetz01, misc01). The
case against it is that doco-cd's API may make it redundant, and it needs an SSH
key on every host. The case for it is that it works today, and doco-cd's
project endpoint may not return image labels (an open question in ADR 0001).

Whichever reader comes first, the source of "what's running" sits behind one
interface, so another can replace it or sit beside it without changing the
views.

## Consequences

- Kuma can be retired at the end of milestone 1, without waiting on doco-cd.
- Drift, PR previews and deploy triggering wait until there is real doco-cd
  state to read.
