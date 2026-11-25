# 0035: Pedant's own errors go to Splat, carrying no credential

**Date:** 2026-11-25
**Status:** Accepted

## Context

When Pedant raised an exception, the only record was the container's log on
grab01. Pedant's heartbeat (ADR 0008) says when Pedant is silent, but not
when one page, one job or one of Solid Queue's threads keeps failing. spool
and clinch send their errors to Splat, Booko's error tracker, over the Sentry
protocol, with `sentry-rails`.

Pedant holds more credentials than they do:
- Push tokens are in URL paths (`/api/push/<token>`, ADR 0012).
- API tokens are in `Authorization` headers (ADR 0025).
- Alert channels have secrets, and an ntfy topic's URL is its own secret.

Pedant also makes requests to every site it checks. With its defaults, the
Sentry SDK adds `sentry-trace` and `baggage` headers to every outgoing
request, even with tracing off. The baggage holds the release, the environment
and the DSN's public key. Pedant would tell every site it checks which version
it runs, which ADR 0029 keeps off the public website. A test against a real
local server showed both headers on a check.

## Decision

**`sentry-rails` sends Pedant's errors to Splat when `SENTRY_DSN` is set.** It
covers exceptions in requests and jobs, and errors Rails reports itself, which
include Solid Queue's dispatcher and scheduler threads
(`register_error_subscriber`). Without a DSN nothing is set up, so development
and test send nothing. The release is `<version>+<revision>`, as in spool and
clinch.

**It sends the least it can** (`config/initializers/sentry.rb`):
- **No trace headers.** The Net::HTTP patch is off, and so is trace
  propagation. Pedant's checks and alerts go out as they did before.
- **No breadcrumbs.** SQL and outgoing requests are where a secret would be.
- **No client IP, cookies, query strings, bodies or SQL values.** Headers named
  like auth, token, session or cookie are always filtered, and so are those
  that carry an address.
- **No session tracking.** Splat has no release health, and drops those
  envelopes.

A push token never reaches an event, because `PushTokenFilter` takes it out of
the path before any Sentry middleware runs, as it does for the log.

`test/integration/error_tracking_test.rb` checks all of this:
- An error in a push carries no token.
- An error on a page carries no session, API token or client address.
- A check sends a real server no trace headers.

**The DSN lives in the stack's `.env` on grab01**, beside `SECRET_KEY_BASE`, and
not in git. booko-services' `grab01/pedant/.env-example` names it. Once doco-cd
deploys grab01, it can move to a SOPS file as other stacks' secrets have.

## Rejected

- **spool's setup as it stands.** It leaves the Net::HTTP patch on, which is
  fine for an app that calls few outside services, but Pedant calls every
  site it watches.
- **Performance tracing.** Spans for outgoing requests would record ntfy's
  topic URL, and Pedant's pages are few and quick. It can be added later,
  with the URLs filtered.
- **Reporting failed checks as errors.** A site being down is Pedant's job
  and goes out as an alert (ADR 0013), not a bug in Pedant.

## Consequences

- An exception in Pedant shows up in Splat with its stack and request line,
  grouped by release.
- An exception that recurs, such as a failing check job, appears once in
  Splat with a count.
- A new outgoing integration (a new alert channel, the fleet reporter) must
  keep its secrets out of exception messages, because those messages are
  sent.
