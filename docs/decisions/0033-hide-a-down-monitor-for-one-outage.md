# 0033: A down monitor can be hidden for one outage, until its next run or for a day

**Date:** 2026-11-24
**Status:** Accepted
**Builds on:** ADR 0013 (alerts once per outage, with reminders), ADR 0016
(monitors are defined in git), ADR 0020 (remind_every)

## Context

On 2026-11-24, pg02's nightly backup failed at 02:46 UTC because an apt
upgrade ran during the dump. The owner knew why straight away. Pedant
still kept the monitor red on the dashboard, and would remind once a day
until the next run, 26 hours later, pushed up again. There was no way to say
"I know" (dkam/pedant#17).

The ways to quieten a monitor were all in `monitors.yml`, through a pull
request: `remind_every: never`, or removing the monitor. Those change what
the monitor is. They suit a monitor retired for good (booko-blog), not one
failed run with a known cause.

## Decision

**A down monitor can be hidden for its current outage, from its page.**
- **Until its next run,** for a push monitor. The hide ends at the next push.
  If that push is up, the monitor recovers as usual. If it's down, a reminder
  goes out at once. If no push comes, the hide ends when the push counts as
  missed (`missed_after`). This is "the period of the test": for a nightly
  job, the hide lasts exactly one night.
- **For 24 hours,** for any monitor. Pushes don't end this kind of hide, so it
  also suits a push monitor that pushes "down" every few minutes.

**While it's hidden:**
- No reminders go out.
- On the dashboard it's muted and listed after the monitors that still need
  attention, and it's counted apart: "2 down · 1 hidden · 30 up".
- It's still `down`. Its state changes, checks and down counts don't change.
- Over MCP it's still down, with `hidden_until` and `hidden_until_next_push`.
  The MCP server can't hide anything, because it's read-only (ADR 0025).

**A hide ends when the monitor recovers,** and the recovery alert goes out as
usual. A later outage starts unhidden. If a hide ends while the monitor is
still down, a reminder goes out straight away, because the hide held back
the ones it would have had. After that, reminders go out every
`remind_every` as before. A monitor with `remind_every: never` stays quiet.
"Show it again" ends a hide early, without a reminder.

**It's kept in SQLite, on the monitor, beside the outage it belongs to**
(`hidden_at`, `hidden_until`, `hidden_until_next_push`). It's about an outage
Pedant observed, not about the monitor's definition, which stays in git. If
the database is wiped, the outage goes too, so nothing is lost that git
should hold (#5).

## Alternatives considered

- **Only "for 24 hours".** This is simpler. Rejected: for a daily job, a
  second failure the next night would stay hidden until the 24 hours ran out,
  and the owner hid the first failure, not the job.
- **Only "until its next run".** Rejected: a push monitor that pushes down
  every 15 minutes (reformers-freshness) would come back after 15 minutes. An
  active check's next run is a minute away.
- **Acknowledge until it recovers, with no end.** Rejected: a monitor that
  never recovers would stay quiet for good. That's a change to the monitor,
  and it belongs in `monitors.yml`.
- **A `paused` field or a pull request to `monitors.yml`.** Rejected for this
  case: a pull request is too heavy for one failed run with a known cause, and
  it changes the definition rather than acknowledging an outage. It's still
  the way to silence a monitor for good.

## Consequences

- Reminders are checked every 5 minutes, so a hide that runs out is noticed
  within 5 minutes. A push ends one straight away.
- The dashboard's order and `list_monitors`' order put hidden monitors after
  pending ones. `counts` still counts them by state.
