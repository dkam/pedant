# 0034: The footer names Pedant's, Rails' and Ruby's versions, when signed in

**Date:** 2026-11-25
**Status:** Accepted
**Amends:** ADR 0029, which rejected a version in the page footer

## Context

ADR 0029 kept Pedant's versions off the website, because pedant.booko.info is
public, and a list of exact versions tells anyone which advisories to try. It
rejected a version in the footer for that reason, and put the full list behind
the MCP API token instead.

The owner wants to see which Pedant is running without asking over MCP: after
a deploy, to check it took, and when reading the page beside the release
notes. Only the owner can sign in (ADRs 0015, 0017), so a page shown only
after sign-in tells nothing to anyone who couldn't already ask over MCP.

## Decision

**Signed in, every page ends with a footer:** "Pedant 0.9.0 (b74ec04) · Rails
8.1.4.1 · Ruby 4.0.10". It shows the version, the first 7 characters of the
revision (left out where it isn't known), Rails and Ruby, and nothing more.

**Signed out there's no footer.** The login and setup pages, the only ones a
stranger reaches, name no version. A test checks both.

The rest of 0029 stands. The OS, kernel, C libraries and gems are over MCP
only, and there's still no public `/version`.

## Rejected

- **The footer on every page, signed in or not.** This is the reason 0029 gave,
  and it still holds.
- **The full about readout on the settings page.** It needs nothing beyond
  the three versions to tell whether a deploy took. The gem list stays where
  an advisory check reads it, over MCP.

## Consequences

- A deploy can be checked by loading any page.
- A new line in the footer must pass the same test as 0029's: harmless
  to the owner, and never shown signed out.
