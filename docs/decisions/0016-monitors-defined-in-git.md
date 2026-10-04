# 0016: Monitors are defined in git, and Pedant reads them

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0004 (milestone 1), ADR 0012 (push monitors)

## Context

Kuma keeps its monitors in its own database, edited in its UI. That list is
hand-maintained and drifts from what actually runs, which is the problem #5
started from.

#5 also sets the rule: git holds intent, and SQLite holds only what was observed
or worked out. If the database is wiped, everything except history must
rebuild from git and the hosts. The monitor list is knowledge about the fleet,
so it falls under that rule. The OIDC and alert settings (ADRs 0011, 0013) are
Pedant's own configuration, so they don't.

## Decision

**Monitors are declared in a `monitors.yml` in the stacks repos
(booko-services, koti-stacks), and Pedant syncs them from there.** To add or
change a monitor, commit to the repo (through a PR, once ADR 0002's flow
exists). Pedant's UI shows monitors but doesn't edit them.

```yaml
# monitors.yml
monitors:
  splat:
    http: http://splat.local:3030/up
  kith:
    name: Kith
    http: http://splat.local:3040/up
    interval: 60        # seconds between checks (at least 20)
    timeout: 10         # seconds; less than the interval
    retries: 1          # failures in a row that are tolerated before "down"
    expect_status: 200-299
    tls_verify: true
  nas-backup:
    push: sha256:9f2c…  # the token's digest (bin/rails pedant:push_token)
    schedule: "0 2 * * *"
    timezone: Australia/Sydney
    grace: 1h
    max_runtime: 3h
  nas-disk:
    push: sha256:41ab…
    interval: 1h
    value: { label: Disk used, unit: "%", warn_above: 80, down_above: 90 }
```

Push fields are described in ADRs 0018 and 0019.

- **Where:** `monitors.yml` at the repo root, and `<stack>/monitors.yml`
  beside a stack's compose file, so a stack's monitors move or go with it.
  Each key must be unique within the repo.
- **What's in the database:** each monitor's observed state (up, down,
  unknown, when that changed, how often it flaps) and its check history. The
  definition columns are a copy of the file, rewritten on every sync.
- **A bad file changes nothing.** If a file doesn't parse, none of its monitors
  are changed or retired. A single invalid entry keeps its last good
  definition. Either way, the error shows on the dashboard.
- **Removing an entry retires the monitor rather than deleting it.** It stops
  being checked, and its history stays. Putting the key back resumes it.
- **Unknown fields are errors,** so a typo like `retires: 3` doesn't quietly
  fall back to the default.
- **Push tokens are credentials (ADR 0012), so git holds only their SHA-256
  digest.** That's settled here and built with push monitors.

**Where Pedant reads the repo from (Pedant's own configuration).** In milestone
1, a monitor source is a local directory: a checkout the owner keeps up to date.
Pedant cloning and fetching from the forge itself comes later, along with the
forge credentials that needs.

## Alternatives considered

- **In the app, like Kuma.** Fastest to build, and how Kuma works. Rejected:
  it breaks the rebuild rule, makes database backups the only copy of the list,
  and keeps the hand-maintained list #5 set out to replace.
- **In the app now, git later.** Rejected: the definitions would have to be
  reworked once, and the git version would still have to exist before Kuma is
  retired.
- **One file per host.** Rejected: monitors belong to stacks more than to
  hosts. A stack can move hosts, and some monitors (a public URL, a push from a
  backup script) don't belong to a host at all.

## Consequences

- The Kuma import (#1) writes `monitors.yml` rather than database rows.
- Changing a monitor takes a commit and a sync (every minute), not a click.
- Monitor sources are kept in Pedant's database, like the OIDC provider. If
  the database is wiped, the owner re-enters the source path, and the monitors
  rebuild from it.
