# 0036: A list_sources tool says which repos Pedant reads, and how each synced

**Date:** 2026-11-25
**Status:** Accepted
**Issue:** dkam/pedant#19

## Context

Over MCP, a source showed only in its monitors' `defined_in`. A source with
no monitors didn't show at all, and neither did the reason. On 2026-11-25 the
question was whether Pedant watched silodrive-infra yet (ADR 0030). Its
`iroh-relay/monitors.yml` was on main and grab01's compose mounted the
checkout, but no monitor came from it. Over MCP there was no telling a source
never added in Settings from one whose directory Docker had made empty, one
whose checkout was behind, or one whose file didn't parse. The settings page
showed all of it, to the owner, in a browser.

## Decision

A sixth MCP tool, `list_sources`, reads `Readout::Sources`, which the
settings page's source list also reads. For each source, by name:

- `id`, `name` and `path`;
- `synced_at`. Sources sync every minute, so an old one means the sync
  isn't running;
- `commit_sha` and `dirty`, both null when the path isn't a git checkout;
- `sync_errors`, a line each;
- `monitors` and `retired_monitors`, counted.

**The path is shown.** ADR 0029 kept paths out of `about`, which describes
the process. A source's path is the owner's own setting and holds no secret,
and it's what tells the right mount from the wrong directory. `/mcp` already
returns the map of the fleet to a token holder (ADR 0025, section 4); a
container path adds little to that.

**Sync errors are shown as written.** They name files, keys and fields. The
push checks say what's wrong with a `push:` value without repeating it, so
neither a token nor its digest reaches them. The endpoint test calls
`list_sources` among the tools whose answers must hold no secret.

It's read-only, like every tool: no "sync now" (ADR 0025, section 2).

## Rejected

- **Sources in `about`.** `about` says what Pedant runs, for checking an
  advisory, and has no paths in it (ADR 0029). Sources are configuration
  and state, which change by the minute.
- **The source's sync state on each monitor in `list_monitors`.** A source
  with no monitors would still not show, and that was the case to answer.
- **Leave the path out.** Then "added, but pointed at an empty directory"
  and "pointed at the wrong directory" look the same.

## Consequences

- "Is Pedant reading this repo yet?" takes one tool call.
- When sources become a git URL and a branch (dkam/pedant#12, ADR 0030),
  those join the readout. A URL with credentials in it must not.
