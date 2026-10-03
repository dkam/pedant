# 0011: OIDC is configured in the app, not through env variables

**Date:** 2026-10-04
**Status:** Accepted
**Changes:** ADR 0009, which ported spool's env-variable configuration

## Context

ADR 0009 made login OIDC only, using spool's implementation, with the first
user claiming the instance by a console setup code (kith's). Spool reads its
provider from env variables (`OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`,
`OIDC_DISCOVERY_URL`), and needs a third "misconfigured" state because env
variables can be half-set.

## Decision

**The OIDC provider is configured in the app, during setup.**

1. While no user exists, boot prints the setup code (ADR 0009).
2. `/setup` takes the code, then the issuer URL, client ID and client secret.
3. Before saving, Pedant fetches the provider's discovery document. A bad URL is
   reported on the form, not discovered at the first login.
4. Pedant then sends the browser through the provider's login. The identity
   that comes back becomes the owner (`iss` + `sub`).

- **The client secret is encrypted at rest** with Active Record encryption, and
  is never shown again or logged. The form shows that a secret is set, never
  the secret itself.
- **Recovery is from the console.** A rake task clears the OIDC settings and
  reopens `/setup`, printing a fresh code. That fits ADR 0009: being able to
  reach the server's console is the highest credential Pedant has.
- **There's one source of configuration.** No env-variable override, so there's
  never a question of which one wins.

Spool's code is still the base for the login flow itself (PKCE, ID token
checks, backchannel logout). Only where the settings come from changes.

## Alternatives considered

- **Env variables (spool's way).** The client secret could then live in
  booko-services as a SOPS file. But Pedant runs off the fleet (ADR 0008) and
  may never be deployed by doco-cd. Env variables also need the
  "misconfigured" state, and a restart to change anything.
- **Both, env overriding the database.** Rejected: two sources means
  diagnosing which one is in effect.

## Consequences

- This is Pedant's own configuration, not fleet intent. Like the users table,
  it doesn't pass ADR 0002's "wipe the database and rebuild from git" test, and
  isn't meant to. That test applies to what Pedant knows about the fleet.
- Database backups contain the encrypted client secret. They're only as safe as
  wherever the Active Record encryption keys are kept.

## Amendment (2026-10-04)

"printing a fresh code" was wrong. As in kith, the code is derived from
`secret_key_base`, never stored, so it's the same code every time setup is
open. That's acceptable: it's accepted only while setup is open, and reading it
needs the console or `secret_key_base`, either of which is already the highest
credential. Changing `secret_key_base` changes the code.

Also as built: setup is open while there's no provider **or** nobody has signed
in. A correct code lets that browser, within 15 minutes, claim the identity it
brings back from the provider. `pedant:reset_oidc` clears the provider and keeps
the users, so an existing identity signs straight back in.
