# 0005: Pedant's issues are on GitHub

**Date:** 2026-10-04
**Status:** Accepted
**Reverses:** the "Issues are on Gitea" part of ADR 0003

## Context

ADR 0003 put Pedant's code and CI on GitHub and its issues on Gitea
(`dkam/pedant`), copying clinch's split. In practice, the Gitea repo is
private, and the `booko` tea login authenticates as the **Claude** user, which
isn't a collaborator on it. The API answers "not found" (2026-10-04), so
sessions can't read or file Pedant's issues there. The `gh` CLI already works
against `github.com/dkam/pedant`.

## Decision

Pedant's issues are GitHub issues on `dkam/pedant`, worked with `gh`. Code, CI,
images and issues are now all in one place.

**Unchanged:** booko-services and its #5 design discussion stay on Gitea. So
does the forge Pedant *talks to* (ADR 0002), which is Gitea first.

## Alternatives considered

- **Keep Gitea issues and add the Claude user as a collaborator** on
  `dkam/pedant`. That would work, but it keeps one project split across two
  forges for no gain, since the code isn't on Gitea.
