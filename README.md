# TradeLab

A trade journal that helps traders track, analyze and improve their performance across stocks, options, futures and crypto.

## Project structure

```
index.html                    Landing page (always light)
favicon.ico                   Browser tab icon (fallback for older browsers)
login.html                    Log in
signup.html                   Create account
forgot-password.html          Password reset request
reset-password.html           Choose a new password (opened from the reset email)
privacy.html, terms.html      Legal pages
contact.html                  Contact form
app/
  trades.html                 Trade log (filters, market tabs, table)
  add-trade.html              Manual trade entry
assets/
  css/
    themes/                   Design tokens only (colors, fonts, radii, spacing)
      daylight.css            Active theme, with night mode colors
      terminal.css …          Alternate looks from the mockups
    base.css                  Reset, element defaults, layout primitives, utilities
    components/               Reusable UI: buttons, forms, cards, navigation, layout, tabs, table
    main.css                  Imports base + all components
    pages/                    One stylesheet per page
  js/
    global.js                 Night mode, menus, dropdowns, mobile nav, password toggles (every page)
    config.example.js         Supabase URL and anon key template (copy to config.js, which is gitignored)
    lib/
      supabase.js             The shared Supabase client (TradeLab.supabase)
      auth.js                 Page guard, log out, account menu, auth form helpers (TradeLab.auth)
    pages/                    One script per page (login, signup, forgot-password, reset-password)
  img/                        Favicon (SVG) and Apple touch icon
design/mockups/               The five design directions
docs/database/                Database schema docs
supabase/                     Migrations and tests
```

## Front-end conventions

- **Styling never hard-codes a color, font or radius.** Use the variables from the theme file. Swapping the theme `<link>` restyles the whole site.
- **Class names follow BEM:** `block`, `block__element`, `block--modifier` (e.g. `card__title`, `btn--primary`).
- **Each page links three stylesheets in this order:** theme, `main.css`, then its own page file.
- **JavaScript hooks use `data-*` attributes**, not classes (e.g. `data-nav-toggle`, `data-action="add-fill"`). Classes are for styling only, so a redesign can't break behavior.
- **Night mode** is `<html data-theme="dark">`. The dark color tokens sit in the theme file under `:root[data-theme="dark"]`, so components need no dark-specific CSS. `global.js` applies the saved choice (or the system setting) and wires every `[data-theme-toggle]` button; it is loaded in `<head>` without `defer` so dark pages don't flash light. The landing page opts out with `data-theme-lock="light"`.
- **`global.js` holds shared UI behavior only.** Page features go in `assets/js/pages/<page>.js`. Database calls go in their own module, not mixed into UI code.
- **Form field names match database columns** (see `docs/database/README.md`), so wiring a form to Supabase is a direct mapping.

## Running locally

It's plain HTML, CSS and JS, so any static server works:

```sh
cp assets/js/config.example.js assets/js/config.js   # then add your Supabase URL and anon key
python3 -m http.server 8000
# open http://localhost:8000
```

Add `http://localhost:8000/**` to the Redirect URLs in Supabase (Authentication > URL Configuration) so the confirmation and password reset links work locally.

## Auth

- Pages that need a signed-in user put `data-auth="required"` on `<body>` and load the Supabase scripts (see `app/trades.html`). Anyone signed out is sent to `login.html?next=<page>` and comes back after logging in.
- `[data-action="sign-out"]` logs out from any page. `[data-user-name]` and `[data-user-initials]` are filled in with the signed-in user.
- Page scripts get the client from `TradeLab.supabase` and wait for the user with `TradeLab.auth.ready.then(user => ...)`.
- Only the anon (publishable) key belongs in `config.js`. Row level security protects the data. Never put the service role key in the front end.

## Database

- Schema and how to change it: [docs/database/README.md](docs/database/README.md)
- Test the migrations locally: `./scripts/db/test-migrations.sh`
