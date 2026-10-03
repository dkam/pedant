# 0009: OIDC login; the first user claims Pedant with a setup code

**Date:** 2026-10-04
**Status:** Accepted

## Context

Pedant shows what runs where and, later, opens deploy PRs. It needs a login,
even on the tailnet.

Two existing patterns fit together:

- **spool's OIDC** (`../spool/docs/auth.md`). It uses the `openid_connect` gem
  directly, with no omniauth, PKCE, and backchannel logout. There's no password
  column, no registration and no reset flow. It was developed against clinch,
  but works with any compliant provider. Spool decides who may sign in with an
  env allowlist (`SPOOL_ALLOWED_USERS` / `_DOMAINS`), and refuses to boot when
  OIDC is configured with an empty allowlist.
- **kith's setup code** (`../kith/app/models/setup.rb`). While no user exists,
  every boot prints a code to the console, and `/setup` accepts it. The code is
  derived from `secret_key_base` (`key_generator.generate_key("kith/setup
  code", 12)`), so it's never stored and every process agrees on it. As soon as
  one user exists, the code stops printing and `/setup` returns 404. Being able
  to read the server's console is the only credential that exists before
  anybody has joined.

## Decision

**Sign-in is OIDC only, using spool's implementation. The first user claims the
instance with kith's setup code.**

1. While there are no users, boot prints a setup code (kith's `Setup`, with the
   key purpose renamed to `"pedant/setup code"`).
2. `/setup` takes the code, then sends the browser through the OIDC login.
3. The identity that comes back becomes the owner, recorded by OIDC issuer +
   subject (`iss` + `sub`), not by email address, since the provider can
   change an email.
4. From then on, `/setup` returns 404, and only users Pedant already knows can
   sign in. A successful provider login by anyone else is refused.

This replaces spool's env allowlist. Who may sign in is stored in Pedant's
database, starting from one console-verified owner, rather than in env
variables that a typo can silently open.

Like spool and kith:

- No passwords, no registration, no reset flow.
- 404, not 403, for `/setup` once claimed.
- The setup form is rate-limited, and the code comparison is constant-time.
- A rake task reprints the setup code for a headless install.

## Alternatives considered

- **Spool's env allowlist.** It works, but it means editing the deployment to
  add a user. It also leaves the boot-refusal checks to catch misconfiguration,
  where the setup code makes "who owns this" explicit from the first boot.
- **Kith's passwords.** Rejected: the OIDC provider already handles credentials,
  and a second credential store is something else to secure.

## Open

- **How further users are added.** Either the owner adds them by email (bound
  to `iss` + `sub` on their first login), or anyone in a provider group claim
  is admitted. Not needed for one user, so it waits.
- **Behaviour with no OIDC configured.** Spool has an `:open` mode for
  development and refuses it in production. Pedant should probably copy that.
