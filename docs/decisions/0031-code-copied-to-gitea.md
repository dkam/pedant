# 0031: Pedant's code is copied to Gitea, and GitHub stays the main copy

**Date:** 2026-11-24
**Status:** Accepted
**Amends:** ADR 0006 (code, CI and images on GitHub, issues on Gitea)

## Context

Under ADR 0006, Pedant's issues are on Gitea (`dkam/pedant`) and its code is
only on GitHub, so an issue on Gitea can't link to the commit that closed it.
On 2026-11-24 Dan asked for the code to be in both.

The Gitea repo `dkam/pedant` already existed for the issues. It's private,
held no code, and had Gitea Actions turned on. Gitea Actions runs a repo's
`.github/workflows`, so pushing would have started Pedant's CI and release
build on Gitea too. That happens on the other repos copied there: clinch's
Gitea copy has 182 runs and splat's has 284, all cancelled.

## Decision

- **GitHub stays the main copy.** CI, the release tags and the
  `ghcr.io/dkam/pedant` images all stay there. Gitea holds a copy of `main` and
  the release tags, beside the issues.
- **Gitea Actions is off for `dkam/pedant`.** Dan turned it off on 2026-11-24;
  it needs a repo admin, which the `booko` login isn't. Leave it off.
- **On tachi, the `github` remote pushes to both.** It has two push URLs,
  GitHub's then Gitea's, so `git push github HEAD:main` updates both. Fetching
  still comes from GitHub only. Every worktree of `~/Development/pedant` shares
  its `.git/config`, so every session's push does this. To set it up in another
  clone:
  ```sh
  git remote set-url --add --push github git@github.com:dkam/pedant.git
  git remote set-url --add --push github ssh://git@git.booko.info:2222/dkam/pedant.git
  git config push.followTags true
  ```
- **Release tags reach Gitea one push late.** CI creates `vX.Y.Z` on GitHub
  after the push that bumps `config/version.rb`. A later `git fetch github`
  brings the tag down, and with `push.followTags` the next push sends it to
  Gitea.

## Rejected

- **Pushing to each by hand,** as clinch is. It relies on remembering: splat's
  Gitea copy stopped on 2026-10-12.
- **A Gitea pull mirror of GitHub.** Gitea makes a mirror as a new repo, so it
  couldn't be the `dkam/pedant` that holds the issues. It also syncs on a
  timer, not on push.
- **A GitHub Actions job that pushes to Gitea.** It would store a Gitea
  credential with write access in GitHub, to save one push URL in a local
  config.

## Limits

- The two push URLs are in tachi's `.git/config`, not in the repo. A clone
  anywhere else pushes only to GitHub until it's set up as above.
- If Gitea is down, a push still reaches GitHub, and git reports an error for
  Gitea. The next push catches Gitea up, because it sends the whole branch.
- Don't commit to Gitea alone (the `origin` remote). Gitea's `main` would then
  have a commit GitHub's lacks, and the next push to Gitea would be rejected as
  not a fast-forward.
