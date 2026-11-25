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
- [`decisions/0021-tcp-monitors.md`](decisions/0021-tcp-monitors.md) adds
  `tcp: host:port` monitors, which only check that the port accepts a
  connection.
- [`decisions/0022-http-body-checks.md`](decisions/0022-http-body-checks.md)
  adds `expect_body` (text to find) and `expect_json` (dotted paths and their
  values) to `http` monitors, for Kuma's keyword and json-query monitors.
- [`decisions/0023-value-forecasts-and-host-reporter.md`](decisions/0023-value-forecasts-and-host-reporter.md)
  gives pushed values a forecast (when free space reaches 0, from hourly
  medians over a day and a week, restarted after a cleanup). Disk space and
  inodes are pushed from a host-reporter stack on each host, separate from
  doco-cd's own.
- [`decisions/0024-grab01-public-website-tailnet-pushes.md`](decisions/0024-grab01-public-website-tailnet-pushes.md)
  runs Pedant on grab01. The website is public at `pedant.booko.info`, and
  servers push over the tailnet to `http://grab01`, which is the only place
  that takes pushes.
- [`decisions/0025-read-only-mcp-server.md`](decisions/0025-read-only-mcp-server.md)
  serves a read-only MCP server for agents, public at
  `pedant.booko.info/mcp` and protected by a token. Its tools read through
  `Readout`, which the HTML views share. Its named bearer tokens are shown
  once, stored as digests, and never expire.
- [`decisions/0027-push-sources-in-monitors-yml.md`](decisions/0027-push-sources-in-monitors-yml.md)
  moves "pushes only from the tailnet" from Caddy into Pedant, per monitor: a
  push monitor's `from:` lists the addresses or ranges that may push to it,
  and without it only the tailnet may. Pedant must see the real client
  address, so a forged `Client-IP` is ignored.
- [`decisions/0028-system-light-and-dark-themes.md`](decisions/0028-system-light-and-dark-themes.md)
  offers System, Light and Dark, kept per browser in localStorage. Views use
  colour roles (`text-ink`, `bg-surface`, `text-bad`), each a `light-dark()`
  pair in the stylesheet, never palette colours; a test enforces it.
- [`decisions/0029-about-tool-over-mcp-only.md`](decisions/0029-about-tool-over-mcp-only.md)
  adds an `about` MCP tool: Pedant's version and revision, Ruby, Rails, OS,
  host kernel, C libraries and every gem, default gems included, for checking
  an advisory. Over MCP only, never on the public website.
- [`decisions/0030-a-source-is-a-repo.md`](decisions/0030-a-source-is-a-repo.md)
  makes a source a git repo, read for both `monitors.yml` and
  `.doco-cd.<host>.yml`, with any number of them (silodrive-infra beside
  booko-services). A host's desired state is the union across sources, a plan
  is a PR in one repo, and every repo that deploys carries the delete guard.
- [`decisions/0031-code-copied-to-gitea.md`](decisions/0031-code-copied-to-gitea.md)
  copies the code to Gitea's `dkam/pedant`, beside the issues: the `github`
  remote pushes to both, Gitea Actions stays off, and GitHub keeps CI, release
  tags and images.
- [`decisions/0032-deployments-read-from-git-at-the-synced-commit.md`](decisions/0032-deployments-read-from-git-at-the-synced-commit.md)
  reads what each host should run from `.doco-cd.<host>.yml` in every source,
  as doco-cd reads it, at the commit the last sync recorded, not from the
  working tree. It's worked out when asked, never stored. A variable in an
  image is filled in from plaintext files only, and one an encrypted file sets
  is shown as written.
- [`decisions/0033-hide-a-down-monitor-for-one-outage.md`](decisions/0033-hide-a-down-monitor-for-one-outage.md)
  lets the owner hide a down monitor for its current outage: until its next
  run (a push monitor) or for 24 hours. While hidden, it sends no reminders
  and is muted on the dashboard. Recovering ends the hide, and a reminder goes
  out at once if it ends with the monitor still down. It's kept in SQLite, since
  it's about an observed outage, not the monitor's definition.
- [`decisions/0034-versions-in-the-footer-when-signed-in.md`](decisions/0034-versions-in-the-footer-when-signed-in.md)
  amends 0029: signed in, every page's footer names Pedant's version and
  revision, Rails and Ruby. Signed out there's no footer, since the site is
  public.
- [`decisions/0035-errors-to-splat.md`](decisions/0035-errors-to-splat.md)
  sends Pedant's own errors to Splat with `sentry-rails` when `SENTRY_DSN` is
  set, carrying no credential. There are no trace headers on checks, since
  their baggage would name the release, no breadcrumbs, and no client IP,
  cookies or bodies. Tests check each of these.
