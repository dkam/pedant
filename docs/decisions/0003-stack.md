# 0003: Stack

**Date:** 2026-10-04
**Status:** Accepted, except the job backend, which is still open

## Decision

The same stack as the sibling apps (`../splat`, `../spool`, `../clinch`), so a
session working across them doesn't have to switch conventions:

- Rails 8.1, SQLite (`sqlite3 >= 2.1`), Propshaft
- Tailwind (`tailwindcss-rails`), Stimulus, Turbo, importmaps. No Node build.
- Plain ERB views, not Phlex. Only gr uses Phlex. Splat's CLAUDE.md lists it,
  but splat's Gemfile doesn't include it.
- Solid Cache and Solid Cable
- Thruster in front of Puma
- `config/version.rb` and file-driven releases follow splat's pattern (see
  `../splat/docs/decisions/0004-file-driven-releases.md`). CI publishes the
  image when the version changes on main.

Not Postgres, Redis or Sidekiq.

## Open: job backend

The candidates are **Solid Queue** and **tuber** (`../tuberq`). Spool already
runs Active Job on tuber, through `lib/active_job/queue_adapters/tuber_adapter.rb`.

The deciding factor is probably **scheduling, not queueing**:

- Uptime checks fire every N seconds per monitor, and a late check is a wrong
  answer about uptime.
- Solid Queue has recurring tasks (`config/recurring.yml`) built in.
- Splat runs tuber with a separate scheduler (`Ingest::Scheduler`,
  `config/schedule.yml`).
- Splat's ADR 0001 records a single-threaded tuber consumer starving every
  other job on its tube. A slow SSH inventory sharing a tube with uptime checks
  would fail the same way, whichever backend is chosen. Keep them on separate
  queues or workers.

Record the choice as a new ADR when it's made.

## CI and registry

**Decision:** Pedant's code is on GitHub (`dkam/pedant`). It builds on GitHub
Actions and publishes to `ghcr.io/dkam/pedant`, the same as splat and spool.
The workflows are copied from `../splat/.github/workflows/`. **Issues are on
Gitea** (`dkam/pedant`), not GitHub. That's the same split as clinch, which keeps
`origin` on Gitea and has a `github` remote.

The deploy target, booko-services, stays on Gitea, so Pedant's forge adapter
(ADR 0002) still targets Gitea first. Where Pedant's own code lives doesn't
change which forge it talks to.

The siblings, for reference:

| App | Forge | CI | Registry |
|---|---|---|---|
| splat, spool | GitHub | GitHub Actions | `ghcr.io/dkam/<app>` |
| clinch | git.booko.info (with GitHub workflows) | GitHub Actions | `ghcr.io/dkam/clinch` |
| c2a2 | git.booko.info, Booko org | Gitea Actions | `reg.tbdb.info/c2a2` |
| gr | git.booko.info | local `bin/build` | git.booko.info |

c2a2's Gitea Actions setup was considered, because the design lives on
git.booko.info and ADR 0001 wants Gitea Actions for the destroy check. That
check runs on booko-services, though, not on Pedant, so it doesn't bind
Pedant's own CI.
