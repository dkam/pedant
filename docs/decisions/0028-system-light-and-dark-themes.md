# 0028: System, light and dark themes, from colour roles

**Date:** 2026-11-23
**Status:** Accepted

## Context

Pedant was light only, styled with Tailwind's stone palette written straight
into the views (`text-stone-600`, `bg-white`). Adding dark mode meant choosing
how the views say what colour something is, and who picks the theme.

The sibling apps do it two ways. Splat puts `dark:` variants beside every
colour and toggles a `.dark` class, cycling light, dark and auto from one
button. Spool names colour roles (`text-ink`, `border-rule`) as Tailwind theme
variables and re-declares them under `[data-theme="dark"]`, with Light and Dark
buttons and no System one: a choice is forgotten when it matches the system.

## Decision

### 1. Views name a role; the stylesheet holds both values

`app/assets/tailwind/application.css` declares colour roles in `@theme`:
grounds (`canvas`, `surface`, `well`), text (`ink`, `ink-soft`, `soft`,
`faint`), lines (`rule-faint`, `rule`, `rule-strong`) and states (`good`,
`bad`, `warn`, each with a `-wash` for badges). Each is a CSS
`light-dark(light, dark)` of Tailwind palette values. Views use only the
roles. Light mode looks as it did, except that inline state text moved one
step darker (red-700 to red-800 and the like), so each state is one colour.

`light-dark()` resolves against the page's `color-scheme`, which is
`light dark` by default (follow the system) and pinned by `data-theme` on
`<html>`. So following the system, including a change at sunset, needs no
JavaScript. `color-scheme` also themes what the stylesheet doesn't reach:
scrollbars, checkboxes, the password reveal button.

`test/views/colour_roles_test.rb` fails on a palette colour in a view, helper
or Stimulus controller, because that one colour would be the same in both
themes and be the thing left unreadable in dark mode.

### 2. Three buttons: System, Light, Dark

The header shows them signed in and out. System is the default and is a real
button: the request was for all three. The choice is kept in localStorage
(`pedant:theme`), so it belongs to the browser: a phone and a laptop can
differ. It isn't a column on the user: it's neither observed nor worked out
(CLAUDE.md's rule for SQLite), and the server never needs it.

An inline script in `<head>` applies a stored choice before the first paint;
Turbo keeps `<html>`'s attributes across visits, so it runs once. The picker
is `data-turbo-permanent`, so the dashboard's morphing refreshes don't reset
the pressed state the controller marks.

## Rejected

- **`dark:` variants (splat).** Every colour is written twice in every view,
  and a view that forgets one is broken only in dark mode, which no test sees.
- **Inverting the stone palette under dark.** No view changes, but
  `bg-white` and `text-stone-900` would stop meaning what they say.
- **Two blocks of variables, light and `[data-theme="dark"]` (spool).** It
  needs a second copy inside `@media (prefers-color-scheme: dark)` to follow
  the system without JavaScript; `light-dark()` keeps each role on one line.
- **Spool's two buttons.** Following the system would be implicit, when it
  was asked for by name.

## Consequences

- `light-dark()` needs Chrome 123, Firefox 120 or Safari 17.5 (2024). Older
  browsers get no colour from the roles.
- A new colour need is a new role in `application.css` with both values,
  not a palette class in a view.
