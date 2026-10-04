# 0023: Value forecasts, and disk space pushed from a host-reporter stack

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0019 (push values); takes up "disk alerts" from ADR 0014

## Context

Disks and inodes run out, and the hosts only find out when a write fails.
A fixed limit doesn't say when that will happen: 90% of a large disk filling
at a gigabyte a week is fine, and 60% of one filling fast isn't. What matters
is when it will be full.

Rubberneck tried to watch CPU, memory and disk as trends. CPU and memory are
bursty, and their trends said nothing useful. Disk mostly fills in one
direction and slowly, so its trend does. That is the part of rubberneck
worth keeping.

ADR 0019 already lets a push carry one value, judged against limits in git.
What's missing is judging where the value is heading, and getting the
numbers from the hosts.

## Decision

### 1. A pushed value can have a forecast

```yaml
misc01-root-free:
  push: sha256:…
  interval: 5m
  value:
    label: Free on /
    unit: GB
    down_below: 5            # the floor: a runaway log beats any trend
    forecast:
      reaches: 0             # the value to project towards
      down_within: 3d        # down if the trend gets there within 3 days
      warn_within: 14d       # warn within 14 days
```

- **Pedant fits a line to the recent values and works out when it reaches
  `reaches`.** The direction comes from where the value is: free space falls
  towards 0, and a percentage used rises towards 100. A trend heading away
  is no forecast.
- **The fit is on hourly medians,** counted back from now, so a dip shorter
  than half an hour, like a backup that writes and then deletes, doesn't move
  the line at all.
- **The fit starts again after a cleanup:** at the latest hour that is
  further from `reaches` than every hour in the 6 before it, by more than 10%
  of its distance. After a prune, the old slope means nothing. A dip that
  recovers only gets back to where it was, so it doesn't restart the fit.
  Two other rules were rejected. Restarting on any jump away: every nightly
  backup's recovery would restart it, so the week-long window would never see
  more than a day. Starting at the best hour of the window, which was built
  first and failed a test: after a partial cleanup (200 GB down to 20, then
  back to 110), last week's 200 is still the best hour, so the warning would
  outlast the cleanup by a week.
- **The time left is read from the fitted line,** not the latest value, so a
  dip in progress barely moves it. The floor (`down_below`) is what watches
  the actual low.
- **Two windows, the last day and the last 7 days, and the sooner forecast
  wins.** The day catches a sudden change in rate; the week catches slow
  growth. A window needs at least 6 hourly values to give a forecast, so a
  new monitor has none for its first 6 hours.
- **Order of judgement:** the job's own down, then the down limits, then
  `down_within`, then the warn limits, then `warn_within`. The message says
  when: "Free on / 18 GB, reaches 0 GB in about 5 days".
- Forecasts aren't disk-specific, like values (ADR 0019).

### 2. Disk numbers are pushed from a host-reporter stack

booko-services gets a `host-reporter/` stack, run on every host: an alpine
container, with the host's `/` mounted read-only, no Docker socket and no
packages. Every 5 minutes it reads `stat -f` for each mount and pushes **free
space** (not percentage used: a percentage can't say how long is left) and
**free inodes**, each to its own push monitor. The repo is laid out by
service rather than by host, so a host's mounts and tokens are in the stack's
`.env` on that host, gitignored like the repo's other `.env` files. They move
to a SOPS env file when the repo has SOPS (ADR 0007). The monitors, which
hold only the tokens' digests, are in `host-reporter/monitors.yml`.

- It's deployed by doco-cd like any other stack. Until doco-cd is installed,
  it's started by hand with `docker compose up -d` from the same files.
- **It isn't part of doco-cd's own compose project.** doco-cd's stack is
  installed by hand, so anything in it would be outside "git is the only way
  to change anything". Once SOPS is in use, its tokens would still have to be
  plaintext on the host, since doco-cd decrypts only the stacks it deploys.
  (Until then they're plaintext in either place.) And the two would fail
  together, when disk reports should keep coming while the deployer is broken.
- doco-cd itself stays a compose stack (as its examples are), installed by
  hand, and doesn't deploy itself for now: a bad commit to its own stack
  would take out the deployer, and only a hand fix would bring it back.
- Filesystems that report no inodes (btrfs, zfs) get no inode monitor.

## Alternatives considered

- **Alert on percentage used.** Rejected as the main signal for the reasons
  above. A floor (`down_below`) stays, for fills faster than a trend.
- **Pull over SSH (`df`).** Nothing to install on the hosts, and `df` only
  reads. Rejected for now: it needs the SSH reader, which is still undecided
  (ADR 0004), while push needs only the forecast. Revisit if the inventory is
  built.
- **Several values per push** (every mount in one request). Still not now
  (ADR 0019): one monitor per mount and per bytes or inodes keeps limits,
  graphs and alerts simple, at the cost of more tokens.
- **CPU and memory trends.** Rejected: bursty, and rubberneck showed their
  trends say nothing. Memory's useful signal is OOM kills, which are events,
  and belong with the docker inventory.
- **Put the reporter in doco-cd's compose.** Rejected; see above.

## Open

- Whether doco-cd adopts a stack first started by hand under the same project
  name, or recreates it. Check on the misc01 trial and note it in
  `docs/learnings/doco-cd.md`.
