# Pedant

The fleet app for Booko's hosts: what runs where, at which version, and whether
it's up. It replaces Uptime Kuma and becomes the dashboard on top of doco-cd.
Named for its most common message: "well, actually, misc01 is running 1.12.2,
and git says 1.12.3."

## Docs

`docs/README.md` says where each kind of note goes. Decisions are numbered,
append-only ADRs in `docs/decisions/`. Read them before changing anything they
cover, and write a new one when you make a choice with rejected alternatives.

## The design lives in Gitea, not here

Booko/booko-services#5 is the design. Read the issue body and all its comments
before making structural decisions:

```
tea api --login booko /repos/Booko/booko-services/issues/5
tea api --login booko /repos/Booko/booko-services/issues/5/comments
```

The comments that matter: 2005 (doco-cd deploys, Pedant watches, git is the
only way to change anything), 2006 (a pull request is the deployment plan) and
2007 (the name). Note: the `booko` tea login currently posts as **Claude**, so
anything written to Gitea through it appears under that name.

Two rules from #5 shape the data model, so keep them in mind from day one:

- **Git holds intent; SQLite holds only what was observed or worked out.** If
  the database is wiped, everything except history must rebuild from git and the
  hosts. Anything that wouldn't belongs in git.
- **Deleting data is never one click or one commit away.** Pedant never exposes
  an action that removes volumes.

## Milestone 1: replace Uptime Kuma (ADRs 0004, 0012)

doco-cd isn't installed on any host yet, so nothing here may depend on its API.
Kuma does two things, and Pedant replaces both. Seed both from Kuma's export
(Pedant issue #1), which hasn't been done yet.

- **Monitors are defined in git** (ADR 0016): a `monitors.yml` at the top of a
  stacks repo, or in a stack's folder. Pedant syncs them from a checkout every
  minute and keeps only what it observed. Its UI never edits them.
- **Active checks:** HTTP (and TCP, TLS expiry) on a schedule, storing up/down,
  when it last changed, and how often it flaps. Code is in `app/models/uptime/`
  (namespaced: a top-level `Monitor` collides with Ruby's).
- **Push monitors:** jobs call `/api/push/<token>?status=up|down&msg=…&ping=…`,
  Kuma's own URL shape, so moving a job means changing only the hostname in
  its curl. Silence past the interval means missed.
- **Splat's check-ins:** splat keeps the Rails apps' own job check-ins. Pedant
  only shows their state.
- **Pedant's own outages:**
  - Pedant's own connection failing is "unknown", not "everything is down".
  - After Pedant is down, a push monitor gets one full interval before it can
    be marked missed.
  - Pedant sends a heartbeat so its own silence raises an alarm (ADR 0008).
- **Alerts:** ntfy and email, configured in the app. Alerts go out on down, on
  recovery, and as reminders while it stays down, never for "unknown" (ADR 0013).
- **Fleet inventory over SSH: optional, undecided.** If built, it uses
  `docker ps` and field-selected `docker inspect`. **Never run a bare
  `docker inspect` or read `.Config.Env`, because it returns secrets in
  plaintext** (ADR 0007).

Later milestones, once the doco-cd trial on misc01 exists: read doco-cd's API,
compare desired state (`.doco-cd.<host>.yml`) with the running state and flag
drift, PR previews, and triggering deploys after a merge. Keep the source of
"what's running" behind an interface, so the SSH reader and a later doco-cd
reader are interchangeable.

Also eventual: **a CLI and an API**, so scripts and agents can ask "what runs
where, at which version, and is it up" without the web UI. They follow the same
rules as the UI:
- Reads are open to any authenticated client.
- Any change is a PR against booko-services (ADR 0002), never a direct deploy.
- Nothing removes volumes (ADR 0001).

An MCP server is an option for the agent-facing side. If it's built, use the
official `mcp` gem, as splat does (`app/mcp/splat_mcp_server.rb`, served at
`/mcp`) and spool does (`bin/mcp` over stdio, tools in `app/mcp`, see
`../spool/docs/mcp.md`). Don't hand-roll the protocol: splat's hand-rolled
server got stuck on the 2024-11-05 spec. Keep controllers thin enough that the
HTML and JSON views share one query layer, so the API isn't a retrofit.

## Stack

Matches the sibling apps in `../` (splat, spool, clinch):

- Rails 8.1, SQLite (`sqlite3 >= 2.1`), Propshaft
- Tailwind (`tailwindcss-rails`), Stimulus, Turbo, importmaps. No Node build, and
  no Phlex: plain ERB views.
- Solid Cache, Solid Cable
- Thruster in front of Puma in the container
- **Jobs: Solid Queue** (ADR 0010), using recurring tasks in
  `config/recurring.yml`. Checks get their own queue, so they never wait
  behind slow work.

Not Postgres, not Redis, not Sidekiq.

## Versioning and builds

- `config/version.rb` defines `Pedant::VERSION`, a SemVer constant bumped by
  hand, readable without booting Rails
  (`ruby -e "require './config/version'; puts Pedant::VERSION"`).
- **Releases are file-driven** (see
  `../splat/docs/decisions/0004-file-driven-releases.md`): CI publishes when
  `config/version.rb` changes on main, and tags the commit `vX.Y.Z`.
- Image tags are `:vX.Y.Z` (immutable), `:latest` (newest release; never moved
  by a `-dev` version) and `:dev` (newest build from main).
- The image carries `org.opencontainers.image.version` and `.revision` labels.
  Pedant reads these labels on other apps, so it should carry them itself.
- `GIT_SHA` build arg, read at boot by `config/initializers/revision.rb`.
- **Code and CI are on GitHub; issues are on Gitea** (ADR 0006). It's the same
  split as clinch.
  - The code is at `github.com/dkam/pedant` (git remote `github`). CI is GitHub
    Actions, and images go to `ghcr.io/dkam/pedant`.
  - Copy splat's `.github/workflows/build.yml` and `ci.yml`, not its `bin/build`,
    which pushes to `reg.tbdb.info` and isn't splat's real release path.
  - Pedant's issues are in Gitea at `dkam/pedant`. Use
    `tea --login booko --repo dkam/pedant`. Don't use GitHub issues.
  - The design discussion (Booko/booko-services#5) and the booko-services repo
    that doco-cd will watch are on Gitea too.

## Where it runs and who can log in

- **Host:** off the fleet (not hetz01 or misc01), on the tailnet only. Which
  machine doesn't matter to the code (ADR 0008).
- **Login:** a password for one owner, or OIDC, chosen at setup. Only the
  chosen one works (ADR 0015). No sign-up, no reset by email.
  - The owner claims the instance with a setup code printed to the console,
    ported from `../kith` (`app/models/setup.rb`, ADR 0009).
  - OIDC is ported from `../spool` (`docs/auth.md`). The provider is entered
    in the app, with the secret encrypted, not in env variables (ADR 0011).
  - The console is the way back in: `pedant:reset_password`,
    `pedant:reset_oidc`.
- **SSH (if the inventory is built):** read-only commands only. Pedant never
  runs anything on a host that changes state over SSH.

## Development

`bin/dev` serves on **port 3036** (clinch is on 3035), and runs `bin/jobs`, so
checks run in development as they do in production (Solid Queue and Solid
Cable have their own development databases). Clinch's redirect URI for
a local Pedant is `http://localhost:3036/auth/callback`. While setup is open,
starting the server prints the setup code; `bin/rails pedant:setup_code` prints it again, and
`pedant:reset_password` and `pedant:reset_oidc` reopen it.

## Not available on this machine

- **rubberneck** isn't checked out, so its liveness model (#5 suggests reusing
  it: a state read as "did it change, and how often does it flap") can't be
  read from here. The idea is described in #5 section 1; build from that
  description.
