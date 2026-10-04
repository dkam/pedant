# Pedant docs

Same layout as `../splat/docs`, which explains the reasoning at length. In
short, documents are sorted by how fast they go stale.

## Where does this note go?

Ask in order; the first match wins.

**Is it about *our* code?** → A code comment, not a doc. A doc that restates the
code goes stale while the code moves on.

**Is it a fact about a *tool* (doco-cd, SOPS, docker inspect, SQLite, tuber)
that would still be true on another project?** → `learnings/`, one file per
tool. Every claim names how to verify it.

**Is it a choice we made, with alternatives we rejected?** → `decisions/`,
numbered and dated. A **Proposed** ADR is a draft and may be edited until it's
accepted. Once **Accepted**, ADRs are append-only. A later decision that reverses one
gets a new ADR that links back. A fact the ADR got wrong gets a dated
`## Amendment` section at the end; never edit the body.

**Is it an external spec we didn't write (doco-cd's API, Gitea's webhooks)?** →
`reference/`.

**Is it a task?** → The issue tracker, not here. Pedant's issues are on Gitea
(`dkam/pedant`), not GitHub (ADR 0006).

## Layout

| Path | What | Decay |
|---|---|---|
| `decisions/` | Numbered, dated ADRs. Append-only | None: explicitly historical |
| `learnings/` | Durable facts about tools we depend on | None |
| `reference/` | External specs | Tracks upstream |
| `archive/` | Superseded docs, with a `> **SUPERSEDED**` banner | Already dead |

Directories other than `decisions/` are created when their first file is
written.

## Design source

Booko/booko-services#5 and its comments are the original design discussion.
ADRs 0001 and 0002 record the decisions taken there, so they're readable
without Gitea access. The issue remains the place for discussion.

## Index

**Learnings**

- [`learnings/sops.md`](learnings/sops.md): with SOPS dotenv files, variable
  names and recipients are plaintext. Encrypting needs only public keys,
  editing a value needs a private key, and values are authenticated.
- [`learnings/docker.md`](learnings/docker.md): `docker inspect` returns
  environment values (secrets) in plaintext, and `docker ps --format json`
  doesn't, and it does show labels inherited from the image.
- [`learnings/doco-cd.md`](learnings/doco-cd.md): its Docker socket mount makes
  it root on each host. Destroy and volume defaults differ by path, the API key
  can do everything, run history is in memory, and its built-in MCP server
  stays off. From its docs; not yet run.

**Decisions**

- [`decisions/0001-doco-cd-deploys-pedant-watches.md`](decisions/0001-doco-cd-deploys-pedant-watches.md)
  covers doco-cd (not Komodo) applying compose stacks from git on each host,
  with Pedant on top as observer and history. Git is the only way to change
  what runs, and deleting data is never one commit away.
- [`decisions/0002-pull-request-is-the-deployment-plan.md`](decisions/0002-pull-request-is-the-deployment-plan.md)
  says a deployment plan is a PR in the forge, not a database record. SQLite
  holds only what was observed or worked out.
- [`decisions/0003-stack.md`](decisions/0003-stack.md) is the stack: Rails 8.1,
  SQLite, Tailwind, Stimulus, importmaps, Solid Cache and Solid Cable, matching
  the sibling apps. Code and CI are on GitHub, with images on ghcr.io. Jobs per
  ADR 0010.
- [`decisions/0004-milestone-1-without-doco-cd.md`](decisions/0004-milestone-1-without-doco-cd.md)
  makes milestone 1 uptime checks, replacing Kuma, without doco-cd. The SSH
  inventory is optional and undecided.
- [`decisions/0005-issues-on-github.md`](decisions/0005-issues-on-github.md)
  (**superseded by 0006**) moved Pedant's issues to GitHub, because the Claude
  user couldn't see the private Gitea repo.
- [`decisions/0006-issues-back-on-gitea.md`](decisions/0006-issues-back-on-gitea.md)
  moves issues back to Gitea, now that the Claude user is a collaborator.
- [`decisions/0007-pedant-never-decrypts.md`](decisions/0007-pedant-never-decrypts.md)
  says Pedant holds no age private key, shows secret changes by variable name
  only, doesn't edit secrets, and never fetches environment values from
  `docker inspect`.
- [`decisions/0008-runs-off-the-fleet.md`](decisions/0008-runs-off-the-fleet.md)
  runs Pedant off the fleet, on the tailnet, with the host deliberately left
  open. Pedant's own outage reads as "unknown", and a heartbeat watches the
  watcher.
- [`decisions/0009-oidc-login-claimed-by-setup-code.md`](decisions/0009-oidc-login-claimed-by-setup-code.md)
  makes login OIDC only (spool's code). The first user claims Pedant with a
  console setup code (kith's), and after that only known users sign in.
- [`decisions/0010-solid-queue.md`](decisions/0010-solid-queue.md) picks Solid
  Queue over tuber: recurring tasks are built in, and a monitor should depend
  on as little as possible.
- [`decisions/0011-oidc-configured-in-app.md`](decisions/0011-oidc-configured-in-app.md)
  enters the OIDC provider in `/setup` and stores it in the database with the
  secret encrypted, not in env variables.
- [`decisions/0012-push-monitors.md`](decisions/0012-push-monitors.md) has
  Pedant take over Kuma's push monitors on Kuma's own URL shape, so migrating
  a job is a hostname change. Splat keeps the Rails apps' check-ins.
- [`decisions/0013-alerts-by-ntfy-and-email.md`](decisions/0013-alerts-by-ntfy-and-email.md)
  sends every alert to ntfy and email, configured in the app. Alerts go out on
  going down, on recovery, and as reminders while it stays down, never for
  "unknown".
- [`decisions/0014-dockhand-rejected-ideas-kept.md`](decisions/0014-dockhand-rejected-ideas-kept.md)
  rejects Dockhand for its BSL licence, and lists ideas worth taking from it
  (written fresh, not copied): an outbound-only agent, scoped API tokens, an
  activity log, disk alerts, CVE scans in the PR check, adopting stacks.
- [`decisions/0015-password-or-oidc.md`](decisions/0015-password-or-oidc.md)
  lets setup choose a password for one owner, or OIDC, and only the chosen one
  works. Switching from a password to OIDC is in settings; the console resets
  either.
- [`decisions/0016-monitors-defined-in-git.md`](decisions/0016-monitors-defined-in-git.md)
  defines monitors in a `monitors.yml` in the stacks repos. Pedant syncs from
  it and keeps only observed state. Removing an entry retires the monitor;
  push tokens go in as digests.
- [`decisions/0017-password-sign-in-takes-an-email.md`](decisions/0017-password-sign-in-takes-an-email.md)
  gives the password owner an email to sign in with, and settles that a user
  has a password or an OIDC identity, never both.
- [`decisions/0018-push-monitors-as-built.md`](decisions/0018-push-monitors-as-built.md)
  records how push monitors were built: digest lookup, tokens kept out of
  logs, Kuma's status rules, grace, and forgiveness after Pedant's own outage.
- [`decisions/0019-push-values-runs-and-schedules.md`](decisions/0019-push-values-runs-and-schedules.md)
  adds values with units and limits, run times with `max_runtime`, and cron
  schedules to push monitors.
- [`decisions/0020-alerts-as-built.md`](decisions/0020-alerts-as-built.md)
  alerts once per outage (down, reminders, recovery), never for unknown, with
  per-monitor `remind_every`, encrypted channel secrets, and every delivery
  attempt recorded.
