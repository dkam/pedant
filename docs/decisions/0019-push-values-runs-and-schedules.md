# 0019: Push values, runs and schedules

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0012 and ADR 0018

## Decision

Kuma's push monitors fall short in three ways, and Pedant's go further. Each
is an addition: a Kuma-style push still works unchanged.

- **Values with units.** A push can carry `value=87`. monitors.yml gives it a
  label, a unit and limits:
  `value: { label: Disk used, unit: "%", warn_above: 80, down_above: 90 }`
  (or `warn_below` / `down_below`). The limits live in git, never in the push,
  so a script can't loosen its own. Past a down limit is down; past a warn
  limit is the new **warn** state (not a failure, not a flap, and no alert
  unless that's decided later). A value that isn't a number is down, since the
  script is broken. The job's own `status=down` wins over its value. Kuma's
  `ping` still means milliseconds. Values are graphed in their own unit.
  Rubberneck is meant to take over disk monitoring eventually; values aren't
  disk-specific.
- **Runs.** `status=start` marks the start of a run and changes nothing else.
  The finish records the run's duration, which is graphed. With
  `max_runtime: 3h`, a run still going after that is down ("Started 3 hours
  ago, still running") without waiting for the interval.
- **Schedules.** `schedule: "0 2 * * 1-5"` with a required `timezone`, in
  place of `interval`. A push is expected after each scheduled time plus
  grace, so the days a job doesn't run aren't missed. Grace has to cover the
  job's run time.
- Durations in monitors.yml can be written `30s`, `5m`, `3h` or `1d`.

## Alternatives considered

- **Limits in the push** (`value=87&max=90`). Rejected: a script could loosen
  its own limit, and limits would change without review. They're in git
  (ADR 0016).
- **Several values per push.** Not now: one value per monitor keeps each one's
  limit, graph and alert simple. Three disks are three monitors.
