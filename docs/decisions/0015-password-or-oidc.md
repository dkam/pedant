# 0015: The owner signs in with a password or OIDC, chosen at setup

**Date:** 2026-10-04
**Status:** Accepted
**Changes:** ADR 0009, which made login OIDC only, with no passwords

## Context

ADR 0009 made OIDC the only way in. For a single-owner tool on the tailnet,
that makes an identity provider a hard requirement, and it creates a loop:
clinch runs on the fleet Pedant watches, so if clinch is down, Pedant is
unreachable at the moment it's needed to see why.

"No login at all" was never an option. Pedant holds push tokens (each one a
credential, ADR 0012) and alert settings, including the SMTP password and ntfy
token (ADR 0013). Anything else on the tailnet could read them.

## Decision

**Setup offers two ways to sign in. The one chosen is the only one that
works.**

- **A password** for one owner account. Hashed with bcrypt
  (`has_secure_password`), 12 to 72 characters (bcrypt reads only 72 bytes, so
  longer is refused, not silently truncated), and sign-in is rate-limited.
  There's no sign-up and no reset by email.
- **OIDC**, exactly as ADRs 0009 and 0011 describe. No password exists, and
  password sign-in is refused whenever OIDC is in use. "OIDC only" is what
  choosing OIDC means.

Both are claimed with the setup code (ADR 0009).

**Switching:**

- **Password to OIDC** is in settings, and needs the current password. It saves
  the provider and sends the browser through its login. The identity that
  comes back is linked to the owner, and the password is removed. Until that
  happens, within 15 minutes, in the same session, the password keeps working.
  An abandoned switch can't lock the owner out, and a stranger can't finish
  someone else's.
- **OIDC to password** is a console job: `pedant:reset_oidc`, then choose a
  password at setup. The owner is kept.

**The console is the way back in,** as with the setup code.
`bin/rails pedant:reset_password` removes the password and signs every session
out. Without a provider, that reopens setup.

**Sessions end when the credential changes.** Each user has a session token,
copied into the session at sign-in and checked on every request. A password
change rotates it (keeping only the session that made the change), and so do
both console resets.

## Alternatives considered

- **OIDC only (ADR 0009 unchanged).** Rejected: it makes an identity provider
  mandatory for a single-owner tool, and couples Pedant's availability to
  clinch's.
- **No login on a trusted network.** Rejected: see Context.
- **Password and OIDC both active.** Rejected: two ways in is two things to
  secure, and "OIDC only" should mean exactly that.
- **Tailscale identity headers (Tailscale Serve's user header).** Not now.
  It's only safe if nothing reaches Pedant except through Tailscale Serve,
  which the code can't check. It could be a third option later.
- **Password reset by email.** Rejected: email would become a way in. The
  console already is one, and the strongest.

## Consequences

- Additional users are still undecided. One password account is the whole
  password option; more people probably means OIDC.
- The password digest and session token are in the database. Like the OIDC
  settings (ADR 0011), they're Pedant's own configuration, not fleet intent.

## Amendment (2026-10-04)

The email for password sign-in, first recorded here, is a new decision and
has moved to ADR 0017.
