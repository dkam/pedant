# 0001: doco-cd deploys from git; Pedant watches

**Date:** 2026-10-03
**Status:** Accepted for the misc01 trial. doco-cd has not been installed or run yet.
**Source:** Booko/booko-services#5, comment 2005

## Context

- No one can say which of misc01 and hetz01 runs what without running `docker ps`
  on both.
- Most containers run `:latest`.
- Uptime Kuma keeps its own hand-maintained URL list, separate from everything
  else.
- Secrets are `.env` files edited by hand on each host.
- The compose dirs on hetz01 (`~/booko-services`) and misc01 (`~/stacks`) are
  drifted clones of booko-services, each with ~26 uncommitted changes.

## Decision

**doco-cd applies compose stacks; Pedant observes, keeps history and compares.**

- One doco-cd agent per host, all polling booko-services `main`. Each host acts
  only on its own `.doco-cd.<host>.yml`, with stacks under `<host>/<stack>/`.
- Secrets are SOPS + age files in the repo. One age key (Dan's) decrypts
  everything, and one key per host decrypts only that host's path.
- **A commit is a deploy, and `git revert` is a rollback.**
- Pedant reads doco-cd's REST API on each host and adds the two things doco-cd
  lacks:
  1. **History.** doco-cd keeps run history in memory only, so a restart loses it.
  2. **Cross-host comparison.** Git's intent beside each host's reality, and drift
     flagged, including containers running that git doesn't list.

### Rule: every change goes through git

A deploy, version bump or move made in Pedant's UI is a **commit** through the
forge API, followed by `POST /v1/api/poll/run` on the host so it doesn't wait
for the next poll. Pedant never tells doco-cd to deploy directly. Restart and
recreate may call the API directly, since they don't change what *should* run.

### Rule: deleting data is never one commit away

- Removal is always written out in full:
  `destroy: {enabled: true, remove_volumes: false}`. The shorthand
  `destroy: true` removes volumes by default.
- A Gitea Actions check on booko-services fails any commit containing
  `destroy: true` or `remove_volumes: true`, and branch protection makes the
  check unskippable.
- **Pedant never exposes `DELETE /v1/api/project/{name}`**, which also removes
  volumes by default. Leftover volumes appear in an "orphaned volumes" list,
  for Dan to remove by hand.
- doco-cd's API is reachable on the tailnet only. Its key is all-or-nothing, so
  consider Caddy in front to allow only the routes Pedant uses.

### Gitea stays outside doco-cd

Gitea and its registry never appear in a `.doco-cd.*.yml`. A commit can't touch
them, and hetz01 never depends on a Gitea that doco-cd itself deploys.

## Alternatives considered

- **Komodo.** It does the whole job, UI included. Rejected because it needs
  MongoDB (or FerretDB on Postgres) and keeps secrets in its own database, which
  cuts across SOPS + age.
- **Build the fleet view into rubberneck.** Proposed in #5 section 1, because
  rubberneck's `liveness` signal is what a Kuma check is. Not taken: rubberneck
  makes declaring a signal a deliberate human act, while a docker-discovered
  service list would have to *propose* signals. Pedant can still borrow the
  liveness model, which reads a state as "did it change, and how often does it
  flap".
- **Nomad.** It would settle where the service list comes from, but it's a much
  larger change. It remains an optional later trial (#5 section 3).

## Unanswered before doco-cd goes on hetz01

- Will doco-cd destroy a compose project it didn't deploy (say, a mistyped
  `name: gitea` with `destroy: true`)? It must refuse.
- Does `/v1/api/project/{name}` include image labels? If not, Pedant needs its
  own read-only route to `docker inspect`. See ADR 0004.
- Does a commit that changes only a bind-mounted file (a Caddyfile) restart or
  reload the container?
- What backs up Gitea's repos and registry off hetz01?
- What happens when an entry is simply removed from the list? Neither docs page
  says.
