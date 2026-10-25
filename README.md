# TradeLab

A trade journal that helps traders track, analyze and improve their performance across stocks, options, futures and crypto.

## Project structure

```
index.html                    Landing page
login.html                    Log in
signup.html                   Create account
forgot-password.html          Password reset request
privacy.html, terms.html      Legal pages
contact.html                  Contact form
app/
  trades.html                 Trade log (filters, market tabs, table)
  add-trade.html              Manual trade entry
assets/
  css/
    themes/                   Design tokens only (colors, fonts, radii, spacing)
      daylight.css            Active theme
      terminal.css …          Alternate looks from the mockups
    base.css                  Reset, element defaults, layout primitives, utilities
    components/               Reusable UI: buttons, forms, cards, navigation, layout, tabs, table
    main.css                  Imports base + all components
    pages/                    One stylesheet per page
  js/
    global.js                 Menus, dropdowns, mobile nav, password toggles (every page)
    pages/                    One script per page (to come)
design/mockups/               The five design directions
docs/database/                Database schema docs
supabase/                     Migrations and tests
```

## Front-end conventions

- **Styling never hard-codes a color, font or radius.** Use the variables from the theme file. Swapping the theme `<link>` restyles the whole site.
- **Class names follow BEM:** `block`, `block__element`, `block--modifier` (e.g. `card__title`, `btn--primary`).
- **Each page links three stylesheets in this order:** theme, `main.css`, then its own page file.
- **JavaScript hooks use `data-*` attributes**, not classes (e.g. `data-nav-toggle`, `data-action="add-fill"`). Classes are for styling only, so a redesign can't break behavior.
- **`global.js` holds shared UI behavior only.** Page features go in `assets/js/pages/<page>.js`. Database calls go in their own module, not mixed into UI code.
- **Form field names match database columns** (see `docs/database/README.md`), so wiring a form to Supabase is a direct mapping.

## Running locally

It's plain HTML, CSS and JS, so any static server works:

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

## Database

- Schema and how to change it: [docs/database/README.md](docs/database/README.md)
- Test the migrations locally: `./scripts/db/test-migrations.sh`
