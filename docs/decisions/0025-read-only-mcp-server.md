# 0025: A read-only MCP server at /mcp, protected by a token

**Date:** 2026-11-22
**Status:** Accepted
**Issue:** dkam/pedant#13

## Context

Agents read Pedant today with `ssh grab01 "docker exec pedant bin/rails
runner …"`. That gives them a shell on grab01 and full write access to the
production app and its database, only to read a few rows. The first real use
is the push-monitor cutover from Kuma (booko-services#11 and others): an agent
watches 13 push monitors check in.

CLAUDE.md has always planned "a CLI and an API, so scripts and agents can ask
what runs where, at which version, and is it up", with an MCP server as an
option for agents, built on the official `mcp` gem as in splat and spool.

## Decision

### 1. MCP first, with a query layer a JSON API can share

Pedant serves MCP at `POST /mcp` with four read-only tools:

| Tool | Answers |
|---|---|
| `list_monitors` | Every monitor's state, since when, and how often it went down in 24 hours and 7 days |
| `monitor_history` | One monitor's state changes and recent checks |
| `push_monitors` | When each push monitor last checked in, what it's expected to do, its value and forecast |
| `recent_alerts` | What was sent, and how each channel's delivery went |

This covers "is it up". "What runs where, at which version" waits for the
inventory or doco-cd (ADR 0004).

**The tools hold no logic.** They read through `Readout`
(`app/models/readout/`), which the dashboard, a monitor's page and the alerts
page also use. A readout gives the HTML views records, and gives everything
else a hash whose fields are written out one by one. A later JSON API renders
the same hashes.

The server uses the `mcp` gem's `handle_json` behind a plain
`ActionController::API` controller, for spool's reasons (`../spool/docs/mcp.md`):
the gem's Streamable HTTP transport adds per-session state and Host/Origin
allow-lists, and has nothing to stream here. A notification gets 202; GET and
DELETE get 405.

### 2. Read-only, and nothing writes through a token

Every tool is annotated `readOnlyHint`, and there are no others. That's not
just "no write tools yet":

- **What runs is changed by a PR against booko-services** (ADRs 0001, 0002),
  and so is what's monitored (ADR 0016). A tool that changed either would be a
  second way in, around review.
- **Pedant's own configuration** (alert channels, sources, sign-in) is changed
  by the owner, in the browser. A token that could change alert channels could
  silence the alerts, which is the one thing a leaked credential for a watcher
  mustn't be able to do.
- **No side effects either**: no "sync now", no "send a test alert". The only
  write a request makes is the token's `last_used_at`, at most every 5 minutes.

A write tool, if one is ever wanted, needs its own ADR and a token that's
issued for it, not these.

### 3. Named bearer tokens, shown once, stored as a digest, never expiring

The owner makes tokens on the settings page, one per client
(say, "laptop Claude Code"), so one can be revoked without the others.

- **Only the SHA-256 digest is stored**, as with push tokens (ADR 0018). The
  token is shown once, carried across the redirect in the (encrypted) flash.
  Lost means revoke and make another. A digest rather than bcrypt, because the
  token is ~250 random bits: there is no dictionary to slow down, and the
  lookup has to be an indexed equality.
- **Prefixed `pedant_`**, so it's recognisable in a config file or a paste.
- **It never reaches a log.** It travels only in the `Authorization` header,
  which Rails doesn't log, and Thruster's request log is already off
  (ADR 0018). A test checks the log of a request.
- **It doesn't expire.** Splat expires a token whose owner hasn't signed in to
  the web UI lately, and splat-aapamilne's MCP stopped working that way: a
  token that stops for a reason that has nothing to do with the token. Pedant
  has one owner, who can see each token's `last_used_at` and revoke it.
  Revocation does what expiry would, when it's actually wanted.
- **Every token reads everything.** There is one owner and nothing narrower to
  scope to.

A missing, unknown or revoked token gets 401 with `WWW-Authenticate: Bearer`,
and a message saying where tokens are made, without saying why this one
failed.

### 4. Public, at https://pedant.booko.info/mcp

`/mcp` is on the internet, like the website (ADR 0024), and the token is what
protects it. grab01's Caddy already sends every path on `pedant.booko.info` to
Pedant, so nothing changes there.

- **The token is the protection either way.** Every request needs one, and
  it's ~250 random bits, so guessing one is hopeless. The login page is on
  the internet already.
- **A leaked token only reads.** That's the difference from pushes, which
  ADR 0024 keeps to the tailnet: a leaked push token can report a dead job as
  up and hide an outage, but an API token can't change or silence anything.
  It can read the map of the fleet (internal hostnames, tailnet addresses,
  what's down) until it's revoked. Its `last_used_at` shows on the settings
  page.
- **Clients off the tailnet can use it**: a Claude Code cloud session, a
  phone, a CI job. claude.ai's web and desktop connectors still can't,
  because they want OAuth, which this doesn't offer.
- **Noise from the internet is cut short.** After 20 refused requests in 10
  minutes, an address gets 429, good token or not, until the window passes.
  It's counted in the process, as pushes are. Behind Caddy, Rails sees the
  client's address from `X-Forwarded-For`, which Caddy sets itself.

## What a tool never returns

Each readout lists its fields, and no record is serialised whole, so a new
column doesn't reach the output by being added. These never appear in any
output:

- an alert channel's `secret` (the ntfy token or the SMTP password) or its
  settings, including the ntfy topic URL, since a public ntfy.sh topic URL is
  effectively a password. A channel is named only by its kind. Delivery errors
  have the channel's URL and secret replaced with `[FILTERED]`, in case a
  server echoed them back.
- a push monitor's `target`, which is its token's digest. An `http` or `tcp`
  monitor's target is shown as written in git. monitors.yml holds no
  secrets (ADRs 0007, 0016).
- the OIDC provider, the users, and API tokens or their digests.

## Alternatives considered

- **A JSON API first.** It would have to be read through curl and docs of its
  shapes. MCP describes its own tools, so an agent finds them without anyone
  writing a client. The readouts make the API a thin controller when there's
  something to use it.
- **A CLI first.** A CLI needs an API to talk to, and a client installed on
  every machine. It comes after the API.
- **MCP over stdio (`bin/mcp`), as spool also offers.** On grab01 that needs
  a shell there, which is what this replaces.
- **Splat's token expiry,** after a period without a web sign-in. Rejected;
  see section 3.
- **On the tailnet only, at http://grab01/mcp**, as pushes are (ADR 0024).
  This was the first draft: a leaked token would be no use off the tailnet,
  and every client today is on it. Rejected: the token is the protection
  either way, a leaked one only reads, and tailnet-only would shut out
  clients off the tailnet for little gain.
- **One token, rotated.** Simpler, but adding a second client would break the
  first.
