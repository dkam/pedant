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

## Milestone 1: works without doco-cd *(open: confirm)*

doco-cd isn't installed on any host yet, so nothing here may depend on its API.
Milestone 1 is the two parts of Pedant that are useful today:

1. **Uptime checks** (the Kuma replacement): HTTP checks on a schedule, storing
   up/down and when that last changed, and how often it flaps. Seed the list from
   Kuma's current monitors. Exporting them (the first step in #5) hasn't been
   done yet.
2. **Fleet inventory over SSH**: for each host, `docker ps` + `docker inspect`
   gives container, image, tag, and the `org.opencontainers.image.version` /
   `.revision` labels. This is #5's `bin/fleet` idea folded into the app.
   Hosts are declared by hand for now (hetz01, misc01).

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
- **Jobs: undecided, Solid Queue or tuber** *(open)*. `../tuberq` holds tuber
  (the server and the gem), and `../spool` runs Active Job on tuber with
  `lib/active_job/queue_adapters/tuber_adapter.rb`, so copy from there if tuber
  is chosen. Note that uptime checks are mostly a *scheduling* problem: Solid
  Queue has recurring tasks (`config/recurring.yml`) built in. With tuber,
  decide what fires the checks on time before choosing.

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
- **Code, CI and issues are on GitHub** at `github.com/dkam/pedant` (git remote
  `github`).
  - CI is GitHub Actions, and images go to `ghcr.io/dkam/pedant`.
  - Copy splat's `.github/workflows/build.yml` and `ci.yml`, not its `bin/build`,
    which pushes to `reg.tbdb.info` and isn't splat's real release path.
  - Pedant's own issues are GitHub issues; use `gh` (ADR 0005).
  - The design discussion (Booko/booko-services#5) and the booko-services repo
    that doco-cd will watch stay on Gitea, and are read with `tea`.

## Where it runs and who can log in *(open)*

- **Host:** not one it manages (so not hetz01 or misc01), so that Pedant stays up
  when they go down. Which host is undecided.
- **Network:** tailnet-only, per #5.
- **Login:** probably OIDC against `../clinch`. `../spool` has a direct OIDC
  implementation (no omniauth, `app/controllers/oidc_auth_controller.rb`,
  `docs/auth.md`) developed against clinch; copy that rather than inventing one.
- **SSH:** the inventory needs an SSH key that can run `docker ps` / `docker
  inspect` on each host. Read-only commands only; Pedant never runs anything on
  a host that changes state over SSH.

## Not available on this machine

- **rubberneck** isn't checked out, so its liveness model (#5 suggests reusing
  it: a state read as "did it change, and how often does it flap") can't be
  read from here. The idea is described in #5 section 1; build from that
  description.
