# 0022: HTTP body checks

**Date:** 2026-10-04
**Status:** Accepted
**Extends:** ADR 0016 (monitors defined in git)

## Context

Kuma's export (#1) has two monitors that look past the status code: a keyword
monitor (tuber's `/metrics` must contain `tuber_`) and a json-query monitor
(splat's `/_health` must have `queue_status` equal to `healthy`). Both were set
up with basic auth in Kuma, but both URLs answer 200 to an anonymous request
(checked 2026-10-04), so credentials aren't needed to migrate them.

## Decision

**An `http` monitor may add `expect_body` (text the body must contain) and
`expect_json` (a map of paths to the values they must have).** The body is
checked only after the status is good, so a 502 still reads "HTTP 502".

```yaml
monitors:
  tuber:
    http: http://100.111.0.120:9101/metrics
    expect_body: tuber_
  splat-queue:
    http: https://splat.booko.info/_health
    expect_json:
      queue_status: healthy
      workers.0.alive: true
```

- A path is keys and array indexes joined with dots. Every path must match,
  and the value must be equal, type included: `"200"` isn't `200`.
- Down messages say what was found: `Body doesn't contain "tuber_"`,
  `queue_status is "degraded", expected "healthy"`, `queues.fetch.paused is
  missing`, `Body isn't JSON`.
- The body is read only when one of these is set, and never past 1 MB: a
  larger body is down rather than read without end.

## Alternatives considered

- **JSONPath or JSONata, as Kuma uses.** Rejected: every expression Kuma has
  is one key compared with one value. A dotted path covers that, needs no gem,
  and can't be written in a way that's hard to read back.
- **One expression and one expected value per monitor, as Kuma has.** Rejected:
  a map lets one monitor check several fields of the same health document.
- **Regular expressions for `expect_body`.** Rejected until one is needed:
  plain text is what the keyword monitor uses.
- **Basic auth on HTTP checks now.** Not needed for the migration (see Context),
  and it means Pedant holding a credential that monitors.yml names. Left for
  when a monitor needs it, with its own ADR.
