# 0027: Which addresses may push is set per monitor, the tailnet by default

**Date:** 2026-11-22
**Status:** Accepted
**Amends:** ADR 0024 (pushes over the tailnet only)
**Issue:** dkam/pedant#14

## Context

ADR 0024 took pushes only over the tailnet. grab01's Caddy enforced it: the
public name answered 404 for `/api/push/*`, and the tailnet names took pushes
only from `100.64.0.0/10`. A leaked token was then no use from outside the
tailnet.

Moving Kuma's push monitors (booko-services#11) found a caller that isn't on
the tailnet. "Backup backups" is pushed weekly by `~/bin/weekly_restic` on
backup.local, a machine at home. Kuma's access log shows it arriving from the
home connection's public address. Caddy can't make an exception for one
monitor, because it sees only the URL, and the token is the monitor.

Putting backup.local on the tailnet would work. But a backup copy that the
fleet can't reach is worth keeping that way: a compromised production host
can't reach it.

## Decision

**A push monitor's `from:` in monitors.yml says which addresses may push to
it. Without `from:`, only the tailnet may.**

```yaml
backup-backups:
  push: sha256:…
  interval: 8d
  from: 116.255.19.189   # backup.local, at home; not on the tailnet
```

- **Entries:** an address, a range (`192.0.2.0/24`, `2001:db8::/32`), or
  `tailnet`. One entry, or a list.
- **`tailnet`** is Tailscale's ranges, `100.64.0.0/10` and
  `fd7a:115c:a1e0::/48`. `from: [tailnet, 192.0.2.7]` takes both.
- **`from:` replaces the default; it doesn't add to it.** A monitor with
  `from: 116.255.19.189` refuses the same token from the tailnet.
- **Refused looks unknown:** a push from an address that isn't allowed gets
  the same 404 as an unknown token, so it doesn't learn that the token is
  real.
- **Rate limits are per token and address,** so pushes refused from elsewhere
  can't use up the real caller's 30 a minute and make it look missed.
- **It's checked at sync like every other field.** An entry that isn't an
  address, a range or `tailnet` is an error, and the monitor keeps its last
  good definition (ADR 0016).
- **The monitor page and MCP's `push_monitors` show it** (`pushes_from`).

The rule moves from Caddy into Pedant. The public name passes `/api/push/*`
through like any other path. The tailnet block keeps its own `remote_ip`
matcher, so Caddy still refuses anything that isn't from the tailnet there.

### Pedant must see the real client address

On grab01, a request passes through Caddy (host network), Docker's port
mapping, and Thruster in the container, before it reaches Puma.

- **Caddy replaces a client's own `X-Forwarded-For`** with the address it
  saw. Checked with a forged header on `caddy:2-alpine` v2.11.6, grab01's
  version.
- **Thruster appends Docker's gateway** (172.x). Rails skips it as a trusted
  proxy, and `remote_ip` is the client. Pedant's own log on grab01 confirms
  this: pushes arrive as grabber01, grabber02, pg01 and hetz01's tailnet
  addresses.
- **Caddy passes a client's `Client-IP` header through untouched.** Two
  settings stop it counting:
  - **`ip_spoofing_check` is off.** With it on, a `Client-IP` that disagrees
    with `X-Forwarded-For` made every page a 500, raised by the request
    logger before any controller. With it off, `X-Forwarded-For` comes first
    and a forged `Client-IP` is ignored.
  - **`fc00::/7` is no longer a trusted proxy.** Rails trusts it by default,
    and Tailscale's IPv6 addresses are in it, so a push from one was skipped
    as a proxy and a forged `Client-IP` behind it was believed. That let a
    tailnet host claim any address.

## Alternatives considered

- **Tailscale on backup.local.** No change to Pedant. Rejected: it joins the
  backup copy to the fleet's network, and keeping it isolated would take an
  ACL that's easy to get wrong.
- **An exception in Caddy for the home address.** One line, no Pedant
  release. Rejected: it would apply to every token, not one monitor, and
  which monitor takes pushes from where belongs in monitors.yml with the
  monitor (ADR 0016).
- **Public pushes for every monitor,** as Kuma had. Rejected: a token leaks
  easily (booko's are in its repo, and pg01's script logs its URL), and with
  it anyone could hide an outage by pushing "up".
- **Trust only loopback as a proxy.** Rejected: Docker's gateway sits between
  Caddy and Thruster, so every client would have looked like 172.x.

## Consequences

- grab01's Caddyfile drops the 404 for `/api/push/*` on the public name, in
  the same booko-services PR that moves grab01 to the release with this
  change. Pedant restarts first, so the public path never opens without the
  check.
- A caller off the tailnet uses `https://pedant.booko.info/api/push/<token>`.
  On the tailnet it's still `http://grab01` (or `http://100.113.145.115`).
- If the home address changes, backup.local's pushes are refused, and the
  monitor is missed after its interval and alerts. The fix is a one-line PR.
- Each tailnet monitor could later be pinned to its own host's address, so a
  leaked token would be no use anywhere else.
