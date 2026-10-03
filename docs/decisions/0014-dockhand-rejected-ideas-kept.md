# 0014: Dockhand rejected for its licence; some of its ideas kept

**Date:** 2026-10-04
**Status:** Accepted
**Adds to:** ADR 0001's alternatives (Komodo)

## Context

Dockhand (dockhand.pro, source at github.com/Finsys/dockhand) is a self-hosted
Docker manager released in December 2025. It's one container with the Docker
socket and SQLite, and it reaches other hosts through Docker's TLS API or
through Hawser, an outbound-only agent. Its features: container and compose
management, deploys from git, logs and metrics, image CVE scanning, restic
backups, external secrets, a REST API, and alerts by email and ntfy. It covers
most of doco-cd plus the Pedant dashboard.

This assessment comes from its homepage, read on 2026-10-04. It hasn't been run.

## Decision

**Don't use Dockhand.** The deciding reason is the licence: BSL 1.1, and its
pricing table lists a commercial usage licence only in the paid tiers ($499 per
host per year). Booko is a business.

The design reasons from ADR 0001 also apply. Dockhand's UI changes things
directly: compose edits, restarts, removals and a shell. So git stops being the
only way to change what runs, and deleting data is a click away.

**Borrow its ideas, not its code.** BSL source is readable, but code copied
from it carries the licence. Read Dockhand for what it does, and write
Pedant's version from scratch. Ideas worth taking, each to be decided in its
own issue or ADR when the time comes:

- **An outbound-only agent** (Hawser) for the fleet inventory (#7). Pedant
  runs off the fleet (ADR 0008), so an agent that connects out to Pedant needs
  no SSH key on the hosts and no inbound port. Pedant's version would be
  read-only, behind a Docker socket proxy that allows only list and
  field-selected inspect, so the ADR 0007 rules hold.
- **An API that the UI itself uses,** with bearer tokens that are scoped,
  expiring, revocable, hashed at rest and never logged. This is the eventual
  CLI and API in CLAUDE.md.
- **A container activity log:** starts, stops, crashes and restarts, recorded
  as observed history. That's what SQLite is for in ADR 0002.
- **Disk usage per host,** with an alert before it fills. A full disk is a
  common cause of failed backups.
- **Image CVE scanning (Grype or Trivy) in the booko-services PR check** (#9),
  so a vulnerable image shows up in the deployment plan before it's merged.
  Dockhand scans at pull time; with git as the plan, the PR is the place.
- **Adopting running stacks:** read a host's running containers and draft the
  compose and `.doco-cd.<host>.yml` for booko-services. That helps bring the
  drifted `~/booko-services` and `~/stacks` directories into git.
- **A Prometheus `/metrics` endpoint.**

## Alternatives considered

- **Dockhand's free tier.** Rejected: its licence appears to exclude
  commercial use.
- **Dockhand paid.** Rejected: the cost is per host per year for features
  Pedant and doco-cd provide, and the design objections above still apply.
