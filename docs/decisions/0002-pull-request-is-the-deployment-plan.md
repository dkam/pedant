# 0002: A pull request is the deployment plan

**Date:** 2026-10-03
**Status:** Accepted. Nothing is built yet.
**Source:** Booko/booko-services#5, comment 2006

## Context

ADR 0001 makes git the only source of desired state. A deployment plan still
needs a diff, discussion, approval and an apply step. A forge PR already has
all four.

## Decision

**A plan is a branch plus a PR in the forge, never a record in Pedant's database.**

### Where things live

- **The forge holds intent.** PR labels carry state:
  - `host:hetz01` and `host:misc01` name the hosts touched. Pedant sets them.
  - `destructive` means the PR removes a service. Set by Pedant and by the CI
    check.
  - `approved` is set by Dan, and is required before a destructive PR can merge.
- **Pedant's SQLite holds only what was worked out or observed:**
  - per-host previews, keyed by PR head sha
  - deploy runs gathered from doco-cd
  - uptime results
  - observed drift

**Test for any new table:** wipe the database. Everything except history must
rebuild from git and the hosts. Anything that wouldn't belongs in git.

### Flow

1. **Propose.** A Pedant action ("bump meili") creates a branch, commits and
   opens a PR, or Dan pushes a branch and opens one himself.
2. **Preview.** A forge webhook tells Pedant about the PR. Pedant diffs the
   `.doco-cd.*.yml` files against `main` and works out per-host changes
   ("hetz01: deploy foo 1.2.0, bump meili 1.12.2 → 1.12.3, remove bar"). It
   stores the result, sets the labels, and comments the preview on the PR.
3. **Apply.** Merge, either in the forge or with a Pedant button that merges
   through the forge API.
4. **Deploy.** The merge webhook tells Pedant, which calls `POST /v1/api/poll/run`
   on each labelled host.
5. **Record.** Pedant follows the doco-cd runs and its own uptime checks, and
   comments the result on the PR.

**Rollback** is a revert of the merged PR. That opens a new PR with its own
preview, so undoing gets the same review as doing.

### Forge adapter

The design only needs PRs, labels, webhooks, branch protection, a CI check and
a merge API. Forge calls sit behind one small interface (open PR, set labels,
comment, merge, verify webhook) with one adapter per forge. Build the Gitea
adapter first, since Gitea is the only forge in use.

- **Forgejo** is a hard fork of Gitea since 2024. Test its adapter separately;
  don't assume the two APIs are identical.
- **GitHub** differs in API shape, not in concepts.

## Alternatives considered

- **Plans as Pedant records**, with Pedant committing on approval. Rejected: it
  duplicates review, discussion and history that the forge already has, and it
  makes Pedant's database a second source of intent.

## Open

- Direct pushes to `main` skip the preview. Either require PRs through branch
  protection, or allow direct pushes and rely on the CI check to block
  destructive changes. Decide once the trial shows how much friction PRs add.
