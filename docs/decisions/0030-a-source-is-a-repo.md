# 0030: A source is a repo, for monitors and deploys, and there can be several

**Date:** 2026-11-24
**Status:** Accepted. Nothing is built yet; the deploy side applies from the
doco-cd milestone.
**Amends:** ADR 0001 (every host polls booko-services), ADR 0002 (a plan is a
PR against booko-services), ADR 0016 (a source is a local directory)

## Context

Silo Drive's services are in their own repo, Silo/silodrive-infra, in another
Gitea org. Its first stack, the iroh relay at `relay.silodrive.io`, runs on
hetz01, behind hetz01's Caddy, which booko-services deploys. The question was
whether Pedant can watch and deploy from more than one repo, or whether
silodrive-infra should be folded into booko-services.

Monitors already work across several repos. ADR 0016 named booko-services and
koti-stacks, and `Uptime::Source` is one directory each: monitor keys are
unique within a source, and a push token across all of them.

The deploy side assumed one repo. ADR 0001 has every host polling
booko-services, and ADR 0002 makes a plan "a PR against booko-services".
doco-cd itself doesn't need that. From its docs (`wiki/docs/` in
kimdre/doco-cd, read 2026-11-24, not yet run):

- **`POLL_CONFIG` is a list of repos,** each with its own `target`, which
  picks `.doco-cd.<target>.yml` in that repo (`Poll-Settings.md`).
- **It destroys only a stack it deployed from the same source,** compared by
  canonical URL and source type, which it keeps in the stack's labels
  (`Deploy-Settings.md`). One repo can't remove another's stack.
- **Git credentials are scoped by domain** (`GIT_AUTH_DOMAINS` in
  `Git-Settings.md`), so repos on the same forge share one credential.

## Decision

**A source is a git repo. Pedant reads both `monitors.yml` and
`.doco-cd.<host>.yml` from it, and there can be any number of sources.**
silodrive-infra stays its own repo and becomes a second source beside
booko-services.

- **One list of sources serves both.** A repo with no `.doco-cd.*.yml` gives
  only monitors (koti-stacks, say). A stack's monitors stay next to its compose
  file (ADR 0016), in the same repo.
- **A source is a git URL and a branch** (dkam/pedant#12). That's a
  prerequisite of the doco-cd milestone, not an option: Pedant needs the URL
  to open PRs, and to match the source URL doco-cd records for each stack.
  Local-path sources stay for development and tests.
- **The list of sources is Pedant's configuration,** kept in its database, as
  ADR 0016 has it. Which repos a host deploys from is in that host's doco-cd
  `POLL_CONFIG`, in git. The two lists can disagree, and that's drift (below).

### A host's desired state combines every source

For drift on hetz01, Pedant reads `.doco-cd.hetz01.yml` from every source and
compares the union with what runs. Compared one repo at a time, each repo
would see the others' stacks as running but undeclared.

- **Each stack is attributed to its source,** by the source URL doco-cd
  records, not by its name.
- **A stack deployed from a repo that isn't a source is flagged,** not
  ignored: a host polls a repo Pedant doesn't read.
- **The same stack name declared for the same host in two sources is an
  error** on the dashboard, like a duplicate monitor key (ADR 0016).

### A plan belongs to one repo

A PR lives in one repo, so previews, labels, merging and reverting are per
repo (ADR 0002's flow, unchanged otherwise). A change that spans repos is one
PR in each, and Pedant doesn't join or order them.

So **config a stack reads belongs in the repo that deploys that stack.** The
relay's Caddy site block is in silodrive-infra today
(`caddy/relay.silodrive.io.caddy`, pasted into hetz01's Caddyfile by hand).
It moves to booko-services, which deploys Caddy. silodrive-infra keeps the
relay.

### Every source that deploys has the same guards

- **Write access to a source's watched branch is root on every host whose
  doco-cd polls it** (`learnings/doco-cd.md`). Adding a repo to a host's
  `POLL_CONFIG` gives that repo's writers root there. For silodrive-infra,
  that's hetz01, which also runs Gitea.
- **booko-services' delete guard is required on each such source:** the CI
  check that fails `destroy: true` and `remove_volumes: true` (ADR 0001), and
  branch protection that makes it unskippable. A repo goes into a host's
  `POLL_CONFIG` only after both are in place.
- **Each source has its own `.sops.yaml`.** Age keys are per host, so one key
  on hetz01 decrypts hetz01's files in every repo. Pedant still never decrypts
  (ADR 0007).
- **Pedant's forge credential needs PR, label and webhook rights on each
  source it plans for,** and read access on the rest. Each source has its own
  webhook pointing at Pedant.

## Alternatives considered

- **Fold silodrive-infra into booko-services.** One repo for Pedant to read,
  and one PR could change the relay and Caddy together. Rejected: it puts
  Silo's services in Booko's repo, and anyone working on Silo would need write
  access to booko-services, which is root on every Booko host.
- **Separate lists of monitor sources and deploy sources.** Rejected: they're
  the same repos, checkouts and credentials, and two lists would drift apart.
  A stack's monitors belong beside its compose file.
- **Drift per repo.** Simpler, since each repo is compared on its own.
  Rejected: every repo sees the others' stacks on a shared host as undeclared,
  so drift is never clean on hetz01.

## Consequences

- `Uptime::Source` moves out of the uptime namespace when the deploy side is
  built. Monitors and deployments both belong to it.
- doco-cd on hetz01 needs one read credential that covers both repos. Gitea
  deploy keys are per repo, so it's a machine account that can read both orgs,
  not a deploy key.
- Adding silodrive-infra as a monitor source needs nothing new: a checkout on
  grab01, mounted read-only into Pedant and added in Settings, the same as
  booko-services until #12 lands.
- Alerts are still global (ADR 0020). The relay's alerts go to the same
  channels as Booko's; routing per source would be a new decision.

## Open, for the misc01 trial

- Which label holds the source URL, and does `docker ps --format json` show it
  (ADR 0007), or only doco-cd's API?
- What doco-cd does when two repos declare the same stack name for one host.
