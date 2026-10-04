# 0024: Pedant on grab01, the website public, pushes over the tailnet

**Date:** 2026-10-04
**Status:** Accepted
**Amends:** ADR 0008, which left the host open and kept all of Pedant on the
tailnet

## Context

ADR 0008 put Pedant on a host it doesn't watch, reachable on the tailnet only,
and named grab01 and the Proxmox box at home as candidates. Choosing the host
raised how people and servers reach it. `pedant.booko.info` was created
pointing at grab01's public address.

## Decision

**Pedant runs on grab01, from `booko-services/grab01/pedant/`.** grab01 isn't
hetz01 or misc01, so it's still off the fleet Pedant watches. grab01 is the
first host in #5's per-host layout: `grab01/<stack>/`, so its config can't
clash with another host's copy of the same stack (as `tinyproxy/` already
did). Its one Caddy, `grab01/caddy/`, serves Pedant and anything else grab01
serves later.

**People use `https://pedant.booko.info`, on grab01's public address.** Caddy
gets the certificate with an ordinary HTTP challenge.

**Servers push over the tailnet, to `http://grab01/api/push/<token>`.** The
public name answers 404 for `/api/push/*`, and the tailnet names answer only
`/api/push/*`, and only to tailnet addresses (`100.64.0.0/10`). Caddy uses host
networking, so it sees the real client address. Plain HTTP is fine there:
WireGuard already encrypts the traffic.

- A leaked push token is no use from outside the tailnet.
- Pushes don't depend on public DNS or the certificate.
- Pedant listens only on `127.0.0.1:3036`, so nothing reaches it except
  through Caddy.
- The monitor source is grab01's existing `~/booko-services` checkout, mounted
  read-only. A host cron line keeps it pulled; Pedant only reads it (ADR 0016).

## Consequences

- **The login page is on the internet.** Sign-in is still one owner's password
  or OIDC, with no sign-up and no reset by email (ADRs 0015, 0017), and the
  setup code is only printed to the console (ADR 0009). The instance has to be
  claimed as soon as it first starts, while setup is open.
- A push job that isn't on the tailnet can't move from Kuma to Pedant by
  changing only the hostname in its curl. Check for those in the Kuma import
  (#1).
- grab01's Docker uses the provider's DNS, not MagicDNS, so monitors should
  name tailnet hosts by address, or the Pedant service gets
  `dns: [100.100.100.100]`.

## Alternatives considered

- **Tailnet only, as ADR 0008 said,** with the record on grab01's tailnet
  address. Rejected: it needs a DNS challenge and a provider API token for
  the certificate, and the website is wanted from anywhere.
- **Pushes on the public name too,** as Kuma's `status.booko.info` takes them.
  Rejected: every server is on the tailnet, so a public push endpoint only
  adds a way in.
- **misc01 or hetz01.** Rejected by ADR 0008: an outage there would take down
  the thing meant to report it.
