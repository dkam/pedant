# 0018: Push monitors as built

**Date:** 2026-10-04
**Status:** Accepted
**Changes:** ADR 0012 (its "compare in constant time" rule); builds on ADR 0016

## Decision

- **The token is looked up by its SHA-256 digest, not compared.** monitors.yml
  holds only the digest (ADR 0016), so Pedant hashes the token it receives and
  finds the monitor by that digest. This replaces "compare in constant time":
  query timing could reveal at most something about the digest, which says
  nothing about the token.
- **Kept out of logs:** `PushTokenFilter` rewrites the path to
  `/api/push/[FILTERED]` before Rails logs the request, and Thruster's own
  request log is off in the image (`LOG_REQUESTS=false`).
- **Rate limit:** 30 pushes a minute per token, counted in the process.
- **Status, as in Kuma:** no status is up, and anything other than `up` is
  down. A push monitor has no retries: the job said how it went.
- **Missed** means no push for `interval` plus `grace` (default 60 seconds).
  `interval` has no default for push monitors; it must be given.
- **Pedant's own outage:** the scheduler records each run. A gap of more than
  2 minutes between runs means Pedant or its job worker was down, so every
  push monitor gets a full interval plus grace from then before it can be
  missed. Active checks aren't affected.
- Both GET and POST are accepted. Whether any script needs POST is still to be
  checked against the Kuma export.
