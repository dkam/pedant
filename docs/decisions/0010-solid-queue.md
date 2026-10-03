# 0010: Solid Queue for jobs

**Date:** 2026-10-04
**Status:** Accepted
**Settles:** the job backend left open in ADR 0003

## Decision

Pedant runs Active Job on **Solid Queue**, the Rails default, which `rails new`
installed (`config/queue.yml`, `config/recurring.yml`, `db/queue_schema.rb`).

## Why not tuber

Tuber is the house queue (spool, splat), and it was the real alternative.

- **Scheduling is the job.** Uptime checks and push-monitor deadlines (ADR
  0012) have to fire on time. Solid Queue has recurring tasks built in. With
  tuber, Pedant would also need a scheduler, as splat built (`Ingest::Scheduler`).
- **A monitor should depend on as little as possible.** Solid Queue lives in
  Pedant's own SQLite. Tuber is a second process that can be down, and Pedant
  would then have to tell "tuber is down" apart from "everything is down".

## Consequences

- Checks must not queue behind slow work. Give uptime checks their own queue
  and worker in `config/queue.yml` (splat ADR 0001 is the cautionary tale: a
  slow job starved everything behind a single consumer).
- If Pedant ever needs tuber's features (job groups, weighted tubes), revisit
  this with a new ADR.
