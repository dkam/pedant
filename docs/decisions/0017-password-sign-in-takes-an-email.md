# 0017: Password sign-in takes an email

**Date:** 2026-10-04
**Status:** Accepted
**Changes:** ADR 0015, where the password owner had no username

## Decision

The password option has an email address too. Setup asks for it, and sign-in
takes email and password (`authenticate_by`, which hashes the password whether or not the email
exists, and the error doesn't say which was wrong). Emails are
stored trimmed and lowercase. Changing it in settings needs the current
password. It's still not a way back in: there's no reset by email, and the
console remains the recovery path. It's also the obvious default recipient
for email alerts (ADR 0013).

## Alternatives considered

- **A password alone, for the one owner** (ADR 0015 as written). Rejected:
  Dan asked for an email, and it gives the owner a name to sign in with and
  a recipient for alerts.

## Also settled

- A user signs in with a password or an OIDC identity, never both. Choosing
  a password at setup drops an identity left by `pedant:reset_oidc`; holding
  both would count the owner as an OIDC user while the password is still the
  way in (a lockout found in review, 2026-10-04).
