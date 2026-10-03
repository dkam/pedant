# 0006: Pedant's issues are on Gitea after all

**Date:** 2026-10-04
**Status:** Accepted
**Supersedes:** ADR 0005

## Context

ADR 0005 moved Pedant's issues to GitHub for one reason: the Claude user that
`tea --login booko` authenticates as couldn't see the private Gitea repo
`dkam/pedant`. Dan has since added the Claude user as a collaborator.
Confirmed 2026-10-04: `tea api --login booko /repos/dkam/pedant` returns the
repo with `pull` and `push` permission and `has_issues: true`.

## Decision

Pedant's issues are on Gitea (`dkam/pedant`), worked with `tea --login booko`,
as ADR 0003 originally had it. Code, CI and images stay on GitHub. This is the
same split as clinch.

Issues therefore sit on the same forge as the booko-services #5 design
discussion. Pedant's code and CI are the only parts on GitHub.

## Note

ADR 0005 was right about the facts when it was written. Its premise was a
permission, not a preference, and fixing the permission removed the reason for
it.
