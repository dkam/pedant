# 0038: Nothing Pedant starts outlives it unreaped

**Date:** 2026-11-26
**Status:** Accepted
**Builds on:** ADR 0037 (sources fetched with git)

## Context

0.12.0 fetched each source with git once a minute (ADR 0037). On grab01,
eight hours after the two sources switched to ssh, Pedant could no longer
fork or start a thread. Every fetch failed with `cannot fork()`, ntfy and the
HTTP checks failed with "Temporary failure in name resolution" (Ruby resolves
a name in a thread of its own), and 14 monitors showed down.

The container's 1008 tasks (its cgroup's `pids.max`) were full: 937 of them
were zombie `git` processes, children of PID 1.

- Every `git fetch` ends by starting `git maintenance run --auto`, and since
  git 2.47 that detaches by default: it forks, its parent exits, and the copy
  starts a new session. With nothing to do, it exits within a millisecond.
- A process whose parent has gone is adopted by PID 1, which must reap it.
  In Pedant's image, PID 1 was thrust, which reaps nothing. So each fetch
  left one zombie, two a minute.
- When a hung fetch is killed (ADR 0037, after 60 seconds), git dies with its
  ssh, and ssh, whose parent is gone, is adopted the same way.

## Decision

**git's housekeeping runs in the foreground.** git runs with
`maintenance.autoDetach=false` and `gc.autoDetach=false` (2.47 reads the
first, older git the second), so a fetch waits for its own maintenance, within
the fetch's timeout, and reaps it.

**The image's PID 1 is tini**, which reaps any process it adopts, whoever
started it. It runs with `-s`, so it reaps as a subreaper even when another
init is PID 1 (compose's `init: true`).

## Alternatives considered

- **`init: true` in the compose file only.** Rejected as the fix: every
  deploy of the image would have to remember it, and it's the image that
  starts git and ssh. It does no harm beside tini.
- **`fetch --no-auto-maintenance`.** Rejected: a fetch every minute
  leaves small packs and loose objects that nothing would repack. A clone
  Pedant never maintains grows without bound.
- **Pedant as a subreaper (`PR_SET_CHILD_SUBREAPER`), reaping in Ruby.**
  Rejected: that writes an init inside a Rails process, and tini is one.
- **Only tini.** Rejected: maintenance would still be detached, outlive the
  fetch, and could run past the 60-second limit with no one to stop it.

## Consequences

- A test runs two fetches in a child that adopts orphans, as PID 1 would,
  and fails if it reaps any. It failed with 2 before the fix.
- A fetch can take longer when git decides to repack, still within the
  timeout. For stacks repos that's rare and quick.
- Pedant's own failure read as its targets being down. Its outage is meant
  to read as "unknown" (ADR 0008), but `Uptime::Connectivity` connects to
  1.1.1.1 and 9.9.9.9 by address, so it needed no name lookup and still
  succeeded. A name that couldn't be resolved for want of a thread counted
  against the monitor. That is not fixed here.
