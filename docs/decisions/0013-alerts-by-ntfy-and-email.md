# 0013: Alerts go to ntfy and email

**Date:** 2026-10-04
**Status:** Accepted
**Settles:** alert delivery, left open in ADR 0008 (Pedant issue #3)

## Context

When a check fails or a push monitor misses, Pedant has to tell someone. Kuma
does this today. Splat already sends both ntfy and email
(`../splat/app/services/ntfy_notifier.rb`, SMTP in its environment config).

Splat's cron monitors show what goes wrong when alerts are sent only once. Splat
opens an issue on the first miss, sends one notification, and stays silent while
the issue stays open (`../splat/app/jobs/monitors/evaluate_job.rb`). Two monitors
(`ReconcileVisibilityJob`, `detailer`) were missed for weeks on that basis: one
notification, easily lost, then nothing.

## Decision

**Alerts go to ntfy and to email. Every alert goes to every configured
channel.**

- **ntfy** is the push to a phone. It's the same request shape as splat's
  notifier: a POST to a topic URL with an optional bearer token, plus Title,
  Priority, Tags and a Click link back to the monitor in Pedant.
- **Email** is the second, independent path. If ntfy is self-hosted on the
  fleet, it goes down with the fleet, and email still gets through.

**When to alert:**

- **On going down,** after the monitor's retry count (Kuma has the same setting,
  so its values carry over in the import, #1). One failed request isn't an
  outage.
- **On recovery,** once, with how long the outage lasted.
- **While still down, as a reminder** at a set interval (daily by default,
  configurable per monitor). This is the lesson from splat: a single alert gets
  lost, and a missed job goes unnoticed for weeks.
- **Never for "unknown".** If Pedant's own connectivity fails, or Pedant was
  down (ADR 0008, ADR 0012's grace interval), there's nothing to alert about
  except Pedant itself, and its own heartbeat covers that.

**Configuration is in the app, like OIDC (ADR 0011).** The ntfy topic URL and
token, and the SMTP server, user and password, are entered on a settings page.
Secrets are encrypted with Active Record encryption and never shown again. A
"send test alert" button sends through each channel, so a broken channel is
found when it's set up, not during an outage.

**Delivery is a job on its own queue** (`alerts`, ADR 0010), with retries. Each
attempt is recorded: which alert, which channel, sent or failed, and the error.
A channel that's failing shows on the dashboard. A failed delivery never stops
the check that raised it.

## Who alerts when Pedant goes quiet

Neither channel can notice Pedant's silence. Pedant checks in to splat as a
cron monitor (the receiver ADR 0008 suggests), and splat's alerting covers it.
Splat's alert-once behaviour applies to that monitor too. That's a splat
problem, so record it in splat's tracker rather than working around it here.

## Alternatives considered

- **ntfy only.** Rejected: if ntfy is hosted on the fleet, an outage of the
  fleet takes out the alert about it.
- **Email only.** Rejected: email is too slow and too easy to miss for "the
  site is down".
- **Alert once, like splat.** Rejected: that's the failure that left two
  monitors missed for weeks.
- **SMTP from env variables, as splat does it.** Rejected for the same reasons
  as ADR 0011: one source of configuration, and Pedant may not be deployed by
  doco-cd, where SOPS files live.
- **Per-monitor channel routing** (this monitor to email only). Not now. Every
  alert goes everywhere until there's a monitor noisy enough to need it.
