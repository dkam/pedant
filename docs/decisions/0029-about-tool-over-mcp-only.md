# 0029: An about tool says what Pedant runs, over MCP only

**Date:** 2026-11-23
**Status:** Accepted

## Context

Advisories drove three of Pedant's last five releases (puma 8.1.2, rack
3.2.9, Ruby 4.0.10). To check whether one applied to the running Pedant, you
had to know which commit was deployed, then read its `Gemfile.lock`, and
still guess at the OS image and the C libraries. Pedant's version was only in
the MCP handshake (`serverInfo.version`), which clients seldom pass on to the
model. Its revision, Ruby, Rails and libraries weren't exposed at all.

## Decision

A fifth MCP tool, `about`, reads `Readout::About`:

- **Pedant:** version, git revision, environment, and when the process
  started (so "did the deploy restart it?" has an answer).
- **Ruby** (version, patch level, platform, YJIT) and **Rails**.
- **System:** the container's OS from `/etc/os-release`, and the kernel and
  architecture. A container shares its host's kernel, so on grab01 that is
  grab01's kernel.
- **Libraries** as loaded in the process: OpenSSL, SQLite, libyaml, zlib,
  libxml2, libxslt.
- **Gems:** Ruby's default gems, then the bundle, then what the process has
  loaded, each later one winning. Default gems (`openssl`, `psych`, …) have
  advisories of their own, and Ruby loads its own copy unless
  `Gemfile.lock` names one, so the lockfile alone would leave them out.

Like every readout, it names its fields; no environment variable, path or
setting appears. It is behind `/mcp`'s API token and nowhere else.

## Rejected

- **A version in the page footer, or a public `/version`.** pedant.booko.info
  is public. A list of exact versions tells anyone which advisories to try.
- **Reading `Gemfile.lock` at the deployed revision.** It misses the default
  gems, the C libraries, the OS image and the kernel. It also describes the
  build, not the running process.
- **An SBOM attached to the image as the only source.** Good for the rest of
  the fleet later, since it needs nothing from the app. But it describes the
  image, so it can't see the kernel or what the process actually loaded.

## Consequences

- Checking an advisory against Pedant takes one tool call.
- A new field is a new line in `Readout::About`, and must not be a secret
  or a path.
