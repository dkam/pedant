# 0020: Alerts as built

**Date:** 2026-10-04
**Status:** Accepted
**Builds on:** ADR 0013 (alerts go to ntfy and email)

## Decision

- **An outage is the unit of alerting.** It opens when a monitor goes down
  (after its retries) and closes when it's up or warn again. One alert when
  it opens, one when it closes ("Down for 12 minutes"), and reminders in
  between. Unknown neither opens nor closes an outage, so down → unknown →
  down alerts once, and up → unknown → up never alerts.
- **Reminders** go out every `remind_every`, set per monitor in monitors.yml:
  a duration of at least 5 minutes, or `never`. The default is a day. None
  while the monitor is unknown. A job checks every 5 minutes.
- **Warn doesn't alert,** as ADR 0019 left it. A monitor going from down to
  warn has recovered.
- **Channels** are one row each (ntfy, email), with non-secret settings as JSON
  and the one secret (ntfy token, SMTP password) encrypted. A blank secret on
  the form keeps the saved one; the saved one is never shown.
- **Email uses the SMTP server on the alerts page,** passed per message, not
  a global setting. Failures must raise (`raise_delivery_errors`), or a failed
  email would be recorded as sent.
- **Links back to Pedant** use the address the alerts page was saved from,
  so there's no separate "Pedant's URL" setting.
- **Delivery** is a job per alert and channel on the `alerts` queue, retried
  five times with growing waits. Each attempt is a row: sent or failed, the
  error, and which attempt. A channel whose latest attempt failed shows on the
  dashboard until one succeeds.
- **Deliveries are queued only once the alert is committed.** The job queue
  is a separate database, so a job queued inside a transaction that rolls back
  would still run.
- **The test button sends straight away** through that one channel and says
  what happened, so a broken channel is found while setting it up.

## Alternatives considered

- **Alert on every down check.** Rejected: one outage would page every
  minute. Reminders cover "still down" at a pace the owner chooses.
- **A global "Pedant's URL" setting for links.** Rejected for now: one more
  thing to configure, and the page's own address is the one the owner uses.
