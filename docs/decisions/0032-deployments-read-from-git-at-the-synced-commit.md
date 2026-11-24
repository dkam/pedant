# 0032: What a host should run is read from git, at the commit a source synced

**Date:** 2026-11-24
**Status:** Accepted
**Builds on:** ADR 0030 (a source is a repo), ADR 0007 (Pedant never decrypts)

## Context

The deployments page (dkam/pedant#16) compares what git says each host should
run with what actually runs. This is the git side. A source is a checkout
(ADR 0016, ADR 0030). On grab01 that checkout is a clone the owner updates by
hand, so it can lag main, and it can have local edits.

doco-cd deploys a host from `.doco-cd.<host>.yml` at the top of a repo: one
stack per YAML document, with a `working_dir`, `compose_files`, `env_files`,
`environment` and `profiles` (`wiki/docs/Deploy-Settings.md` in kimdre/doco-cd,
read 2026-11-24). Pedant has to read the same files the same way, or the
comparison means nothing.

## Decision

**The desired state is read at the commit the source's last sync recorded,
not from the working tree.** It's read through git (`ls-tree` and `cat-file`),
in `Source::Checkout`.
- A hand edit on grab01 isn't taken as intent.
- The page names the commit it read ("booko-services at 278d943"). The page
  and the settings page both say when the checkout has local changes.
- A path is resolved inside the commit's tree, so a `../` in a deploy file
  can't reach a file outside the repo. A `working_dir` that tries is a problem.

**It's worked out when the page is read, and never stored.** Git holds intent
(#5). Reading every stack in booko-services took 137 ms.

**It's read as doco-cd reads it** (`Deployments::Desired`):
- A host is named by its file: `.doco-cd.misc01.yml` is misc01. A
  `.doco-cd.yml` with no host is a problem, because Pedant can't tell which
  host reads it.
- `compose_files` defaults to doco-cd's list. They're read in order, a later
  one overriding an earlier one, and missing ones are skipped.
- A service in a profile the stack doesn't enable isn't deployed.
- A host's stacks are the union across sources (ADR 0030). The same stack
  declared twice for a host is a problem, and both rows are shown.

**A `${VAR}` in an image is filled in from plaintext files only**
(`Deployments::Variables`). The sources are `env_files` in order, then
`environment`, with compose's `:-`, `-`, `:+`, `+` and `?` operators.
- A SOPS dotenv file encrypts values, not keys. Pedant reads its keys to know
  which variables it sets, and shows an image that uses one as written.
- It never reads or decrypts the values (ADR 0007).
- If a file's keys can't be seen, every variable set before it is unknown.
- An image left as written is marked, so step 3 can say "can't compare"
  rather than "differs".

**What would stop doco-cd deploying a stack is a problem. What Pedant can't
see is a note.**
- Problems go in an alert at the top of the page: a file that doesn't parse, a
  stack with no name, no compose file, a missing env file that the deploy
  names, or a duplicate. A problem in one file hides nothing else.
- Notes are shown quietly under the stack: it deploys from another repo
  (`repository_url`), it uses `auto_discovery`, its compose file uses
  `include` or `extends`, or an env file is encrypted. Pedant doesn't follow
  any of these yet, and says so rather than guessing.

## Alternatives considered

- **Read the working tree,** as the monitors sync still does. Rejected: a hand
  edit on grab01 would count as intent, and the page couldn't name what it
  compared against.
- **Read HEAD when the page loads, instead of the recorded commit.**
  Rejected: the page would show a commit that no sync has seen, which could
  differ from the commit the settings page names. Waiting for the next sync
  is at most a minute behind, the same as doco-cd's own polling.
- **Store the desired state in a table at each sync.** Rejected: it's a copy
  of git that can go stale, and reading git is fast enough.
- **Treat every variable as unknown once any encrypted file is listed.** This
  is simpler. Rejected: it hides a plaintext image tag for no reason when the
  encrypted file doesn't set that variable.

## Consequences

- `git` is in the runtime image (added with the commit recording, in 0.8.0).
- The monitors sync still reads the working tree. It moves to the recorded
  commit as a separate change (#16, comment 7413).
- Step 3 compares the running side with this. That's where a stack's inputs
  (its compose files and the files they use) are worked out for drift.
