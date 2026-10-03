# 0007: Pedant never decrypts, and never stores a secret

**Date:** 2026-10-04
**Status:** Accepted
**Affects:** the SSH inventory (milestone 1, ADR 0004), PR previews (ADR 0002)

## Context

booko-services will keep secrets as SOPS + age encrypted dotenv files
(ADR 0001). Each host has an age key that decrypts only its own path, and Dan's
key decrypts everything. doco-cd decrypts on each host at deploy time.

Pedant is a web app that reads every host. If it held a key that could decrypt
everything, or kept copies of decrypted values, it would be the single place
an attacker could read every host's secrets from, which undoes the per-host
key split.

See `docs/learnings/sops.md` and `docs/learnings/docker.md` for the verified
behaviour this rests on.

## Decision

**1. Pedant holds no age private key.** It works only with what SOPS leaves in
plaintext:

- **PR previews show changes to variable names**, e.g. "hetz01/foo: secrets
  added `API_TOKEN`, removed `OLD_KEY`". They never show values.
- **Checks on the encrypted files**, which Pedant reports in the preview. The
  same checks belong in booko-services' CI, next to the destroy check:
  - every file under `<host>/` lists that host's key and Dan's key as
    recipients, and no other host's key
  - no plaintext `.env` or unencrypted secrets file is committed
  - the variable names an encrypted file provides cover what the stack's
    compose file references.

**2. Pedant doesn't edit secrets.** Changing one value needs a private key (see
learnings), so editing from the UI would break rule 1. Dan edits secrets
locally with `sops` and commits them through a PR, like any other change.

**3. Pedant never fetches or stores environment values.** The SSH inventory
uses `docker ps --format '{{json .}}'` and field-selecting
`docker inspect --format …`. It never runs a bare `docker inspect` and never
reads `.Config.Env`. If drift detection on environment ever needs it, fetch
variable *names* only, selected on the host. Never fetch values, and never
hash values, since a hash of a short or guessable secret can be brute-forced.

## Alternatives considered

- **Give Pedant Dan's key, or a key that reads everything, so the UI can edit
  secrets.** Rejected: Pedant would hold every secret in a network-facing app,
  which undoes the per-host key split.
- **Fetch the full `docker inspect` and strip `Env` before saving.** Rejected:
  the secrets still cross SSH and pass through Pedant's memory and logs, and
  one missed code path stores them. Selecting fields on the host makes that
  impossible.
- **OpenBao.** Considered in #5 section 2 and deferred there. It doesn't change
  this decision: Pedant still wouldn't need to read secrets.
