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
  doesn't.

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
  the sibling apps. Code and CI are on GitHub, with images on ghcr.io. The job
  backend is still open.
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
