# 0037: Pedant fetches a source with git, using a deploy key of its own

**Date:** 2026-11-25
**Status:** Accepted
**Issue:** dkam/pedant#12
**Builds on:** ADR 0016 (monitors defined in git), ADR 0030 (a source is a
repo), ADR 0011 (secrets entered in the app, encrypted)

## Context

ADR 0016 made a source a local directory for milestone 1: on grab01,
`/home/booko/booko-services`, mounted read-only and kept current by a
`git pull` in booko's crontab. It said Pedant would clone and fetch for
itself later, "along with the forge credentials that needs". ADR 0030 made
that a prerequisite of the doco-cd milestone: a source is a git URL and a
branch.

The host checkout has already gone wrong. The crontab line was never added, so
from 2026-10-05 to 2026-10-12 Pedant synced a checkout 8 commits behind main,
with no error (#12). That checkout is also grab01's deploy folder. A local edit
there makes `pull --ff-only` fail, `-q` hides the failure, and Pedant syncs the
old files. Since 0.8.0 a sync records the commit it read and whether the
checkout has local changes (ADR 0032). That shows the problem but doesn't fix
it.

## Decision

**A source is a git URL and a branch. Pedant clones it into
`storage/sources/<id>` and fetches at every sync, once a minute.** Local-path
sources stay, for development and tests.

- **The sync reads the clone's working tree, which is forced to the fetched
  commit each time:** `fetch`, `checkout --force --detach`, `clean -ffdx`. The
  monitors sync doesn't change, and nothing left in the clone is read. The
  commit is recorded as before (ADR 0032), so the settings page and
  `list_sources` say "synced 40s ago at b0a3679".
- **A failed fetch changes nothing,** as a file that doesn't parse changes
  nothing (ADR 0016). The monitors keep their definitions, and the source
  keeps its recorded commit. The error goes in the source's sync errors, in
  git's own words. A host key that doesn't match is told plainly, with the
  fingerprint the host offered, rather than as ssh's warning banner.
- **URLs are ssh, `user@host:path`, https or `file://`.** A URL can't carry a
  credential, so none reaches the settings page, a log or `list_sources`
  (ADR 0036). A URL can't start with `-`, and git runs with
  `GIT_ALLOW_PROTOCOL=ssh:https:file`, so `ext::` and options passed as a URL
  are refused. https is for public repos only. A private repo is fetched over
  ssh.

### The credential is a deploy key Pedant makes

- **Adding an ssh source makes an ed25519 key pair for it.** The settings page
  shows the public half, to add to the repo as a deploy key without write
  access. The private half never leaves Pedant. It's encrypted at rest with
  Active Record encryption, as the OIDC client secret is (ADR 0011), and kept
  out of `inspect`, the page and the readout.
- **One key per source.** A deploy key reaches one repo, and is read-only, on
  Gitea, Forgejo and GitHub alike.
- **A fetch offers only that key.** ssh runs with `-F /dev/null`,
  `IdentitiesOnly`, no agent, and `BatchMode`. git runs without the machine's
  global or system config. The key is written to a 0600 file in a temporary
  directory for the fetch, and removed afterwards.

### Host keys are pinned when the source is added

- **Adding an ssh source reads the host's keys once,** with `ssh-keyscan`.
  The settings page shows their fingerprints, to check against the ones the
  forge publishes. Every fetch then runs with `StrictHostKeyChecking=yes`, and
  these keys are its only known hosts. A changed key fails the fetch. It is
  never accepted quietly.
- **The owner can paste the keys instead,** as `known_hosts` lines, say from
  their own machine's `known_hosts` for a host they already trust. Pasted keys
  are kept as they are.
- **The keys are read again only when asked.** Emptying the field reads them
  again, and so does saving a URL that names another host. Changing the
  branch or the path within the repo doesn't.

### Concurrency and time

- A sync from the settings page can run beside the minute's sync, so a fetch
  holds an exclusive lock on `storage/sources/<id>.lock`.
- A git command that runs past 60 seconds is killed, ssh included, and counts
  as a failed fetch. ssh gives up on connecting after 10 seconds.

## Alternatives considered

- **The forges' APIs (contents and trees).** Rejected (#12). Gitea and
  Forgejo share an API, but GitHub's differs, so that's two clients. A sync
  would take several calls to walk the tree, and GitHub rate-limits them. git
  works the same on all three, and fetches the PR refs (`refs/pull/*/head`)
  that ADR 0002's previews will need.
- **Keep the host checkout, and have Pedant flag it as stale.** Partly built
  already (ADR 0032: commit and local changes shown). Rejected as the answer:
  Pedant would still depend on host setup it can't fix, and the checkout stays
  shared with deploys.
- **Read doco-cd's clone.** Rejected: doco-cd isn't installed on grab01
  (ADR 0004), and Pedant shouldn't need the deployer to see its own monitors.
- **The owner pastes a private key.** Rejected: the key would pass through a
  clipboard and a browser form, and could be one that's used elsewhere.
  Making it in Pedant means the private half exists only there.
- **A forge access token (Gitea's, or a GitHub PAT) over https.** Rejected: a
  token reaches every repo its user can read, and it would sit in a URL or a
  credential helper. A deploy key reaches one repo.
- **Accept the host key on first use at each fetch**
  (`StrictHostKeyChecking=accept-new` in a known_hosts file that persists).
  Rejected: a host key that changes or goes missing (the known_hosts file is
  lost with a new container) would be accepted without anyone seeing it. Read
  once, shown and pinned means a change is an error someone sees.
- **A bare clone, read through `ls-tree` and `cat-file`.** That's how the
  deployments side reads (ADR 0032), and the monitors sync could move to it
  (#16, comment 7413). Rejected for now: it changes the monitors sync, and
  #12 asked that it shouldn't. A clone forced to the fetched commit gives
  both readers what they read today.
- **A shallow fetch (`--depth 1`).** It would save space, but stacks repos
  are small, and PR previews will want history and other refs.

## Consequences

- The runtime image has `openssh-client` (ssh, ssh-keygen, ssh-keyscan) beside
  git.
- On grab01, the booko-services source switches to
  `ssh://git@git.booko.info:2222/Booko/booko-services.git`, branch `main`. Its
  deploy key goes on Gitea, read-only. Its host key fingerprints are checked
  against those of a machine that already trusts git.booko.info
  (`ssh-keygen -lF '[git.booko.info]:2222'`). Silo Infra does the same with
  its own repo and key. Once both fetch, the checkout mounts come out of
  `grab01/pedant/compose.yaml`, and booko's crontab line with them.
- **A path source switches to a URL in place,** from its card on the settings
  page ("Fetch it with git instead"). Monitors are matched by key within a
  source (ADR 0016), and a push token can belong to only one source. A second
  source for booko-services would therefore refuse every push monitor the
  first one holds, and start every other monitor's history again. Switched in
  place, it's the same source, and nothing is retired. Until the deploy key is
  added on the forge, its fetches fail and its monitors stay as they were.
- `list_sources` (ADR 0036) shows `url` and `branch` beside `path`. It never
  shows a key.
- A deploy key is per source and per repo. doco-cd on hetz01 still needs a
  machine account that reads both repos (ADR 0030). That's its credential, not
  Pedant's.
- The webhook that would fetch straight after a merge (#12, "later") is
  unchanged: still later.

## Amendment (2026-11-25)

Consequences said booko's crontab line goes once both sources fetch. Only
half of it does. On grab01, `~/booko-services` is also the folder grab01's own
stacks deploy from. Since 2026-11-25 its cron pull, with a deploy key of
booko's own, is how a merged compose change gets there, so the host step
after a merge is only `docker compose pull && up -d`. That pull stays until
doco-cd deploys grab01. What goes is what existed only for Pedant: the
`/sources/` mounts in `grab01/pedant/compose.yaml`, and the
`~/silodrive-infra` checkout with its cron line.
