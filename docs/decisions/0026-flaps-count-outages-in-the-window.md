# 0026: "Down in 24h / 7d" counts the outages that overlap the window

**Date:** 2026-11-22
**Status:** Accepted

## Context

The flap count, the "how often does it flap" half of the liveness model
(ADR 0004, #5), is shown on the dashboard ("Down in 24h"), on a monitor's page
("Down in 24h / 7d"), and through MCP as `down_in_24h` and `down_in_7d`
(ADR 0025). It counted state changes *to* down within the window.

That made a monitor that stayed down read as clean. Booko's blog went down on
2026-10-21 and stayed down, so a month later it showed `down_in_24h: 0` and
`down_in_7d: 0` alongside `state: down`, which reads as "never down" to
anyone who looks at the counts alone. It also counted down → unknown → down
twice, though Pedant only lost sight of the monitor while its own connection
was down, and alerts (ADR 0020) treat that as one outage.

## Decision

**The count is the number of outages that overlap the window:** one already
open when the window began, plus each one that opened in it. An outage is
what alerts already use (`Uptime::Monitor::Outages`): down opens one, up or
warn closes it, and pending and unknown do neither.

`Uptime::StateChange.outages_within` works this out for many monitors and
windows at once, in two queries. `Uptime::Monitor#flaps` and
`Readout.flaps_for` both call it, so the pages and MCP can't disagree.

## Alternatives rejected

- **Keep counting changes to down, and let `state` and `state_since` say it's
  still down.** That is accurate as a count of transitions, but the label says
  "Down in 24h", and the blog was down for all of those 24 hours.
- **Time spent down in the window** (downtime minutes or availability %).
  Useful, but it answers "how much", not "how often". It could be added as a
  field of its own later, beside the count.
- **Store outages as records.** It would make the count a simple query, but
  the state changes already hold everything needed, and a table derived from
  them is one more thing to keep in step.
