# 0021: TCP monitors

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0016 (monitors defined in git)

## Context

Kuma's export (#1) has seven active `port` monitors: Postgres on three hosts,
PgBouncer, two Redis instances and beanstalkd (tuber). None of them speak HTTP,
so Pedant needs a check that only asks whether the port accepts a connection.

## Decision

**A `tcp: host:port` entry opens a connection and closes it.** Up if it
connects within the timeout; down with the reason ("Connection refused",
"Timed out after 10s", a name that doesn't resolve) otherwise.

```yaml
monitors:
  pg01-psql:
    name: PG01 PSQL
    tcp: 100.122.23.60:5432
```

- It takes the same timing fields as `http` (`interval`, `timeout`, `retries`,
  `remind_every`) with the same defaults, and nothing else. An `http` field
  such as `expect_status` on a `tcp` entry is an unknown-field error.
- The target is one string, `host:port` (or `[v6 address]:port`), in the same
  style as `http: <url>`.
- Nothing is sent once connected. A protocol-level check (a Postgres
  handshake, Redis `PING`) is a later, separate check type if it's ever needed.

## Alternatives considered

- **Separate `host` and `port` fields, as Kuma has.** Rejected: every other
  kind names its target in its own key, and one string reads as it's typed into
  `nc`.
- **Speaking each service's protocol.** Rejected for now: a refused or
  unanswered connection is what Kuma catches today, and the protocols differ
  for each service.
