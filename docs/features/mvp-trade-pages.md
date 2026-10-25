# MVP features: Add Trade and Trade Log

This is the build list for the two core pages. The HTML and CSS are done:

- `app/add-trade.html`
- `app/trades.html`

What's left is the JavaScript and the Supabase calls. Each feature lists what it does, the tables it touches, and the hooks already in the markup.

**Priority**

- **MVP** means it must ship for launch.
- **Later** means it's planned but can wait until after the beta.

The schema is described in [`docs/database/README.md`](../database/README.md).

---

## 0. Groundwork (before either page)

Both pages need a signed-in user, because row level security hides every trade from anonymous visitors.

| # | Feature | What it does | Files / data |
| --- | --- | --- | --- |
| G1 | Supabase client | One shared client created with the project URL and anon key. | `assets/js/lib/supabase.js` |
| G2 | Auth pages | Wire up three pages: `login.html` uses `signInWithPassword`, `signup.html` uses `signUp` with `options.data.full_name`, and `forgot-password.html` uses `resetPasswordForEmail`. Errors go in the existing `.field__error` slots and the `role="alert"` banner. | `auth.users`. A trigger creates `profiles` on sign-up. |
| G3 | Auth guard | On every `app/` page, `getSession()`. If there is no session, redirect to `../login.html?next=<current page>`. Login sends the user back to `next`. | |
| G4 | Log out | Clicking `[data-action="sign-out"]` calls `signOut()`, then goes to `../index.html`. | |
| G5 | Account menu | Fill in the avatar initials and name. | `profiles.display_name` |
| G6 | Formatting helpers | Write the shared display helpers (see the list below this table). | `assets/js/lib/format.js` |

The G6 helpers:

- **Money:** `+$1,375.00` / `-$170.00`. Always show the sign.
- **Prices:** precision depends on the asset class.
- **R-multiple:** shown as `2.75R`.
- **Hold time:** for example `1h 12m`.
- **Dates:** in the user's time zone.
- **Instrument labels** for display:
  - Option `AAPL  261218C00150000` becomes `AAPL 150C Dec 18`.
  - Future `ESZ6` becomes `ES Dec 26`.

Suggested JS layout:

- `assets/js/pages/add-trade.js` and `assets/js/pages/trades.js` handle the UI.
- `assets/js/data/trades.js` holds every Supabase query, so the pages never call Supabase directly.

That split keeps the move to React/Next.js simple: the data module moves over almost unchanged.

---

## 1. Add Trade (`app/add-trade.html`)

**What the user does:** picks a market, enters the symbol and direction, adds one or more fills, then optionally adds risk, setup, tags, lists, notes and screenshots, and saves.

**What the database does:** P&L is never typed in. It is calculated from the fills by the database.

| # | Feature | Priority | What it does | Data | Hooks in the HTML |
| --- | --- | --- | --- | --- | --- |
| A1 | Load form options | MVP | On page load, fill the Account select, the Setup select, the tag suggestions and the list checkboxes. Show list usage as "1 of 2 lists used". | `broker_accounts` (where `is_archived = false`), `setups` (where `is_archived = false`), `tags`, `trade_lists`. For the limit, read `plans.limits.max_trade_lists` through `profiles.plan_id`. | `#broker-account` (`name="broker_account_id"`), `#setup` (`name="setup_id"`), `[data-tag-suggestions]`, `[data-list-choices]`, `[data-list-usage]` |
| A2 | Market switch | MVP | No JS is needed: CSS (`:has()`) shows the option fields and changes the labels. On submit, only send option fields when the market is `option`. | | `name="asset_class"` radios (`#market-stock`, etc.) |
| A3 | Fills: add and remove | MVP | "Add fill" clones `#fill-template` and replaces `__INDEX__` with the next index. Remove deletes the row, but keep at least one. Default the first fill's side from Direction (buy for long, sell for short) and its time to now. | | `[data-fills-list]`, `[data-fill]`, `[data-action="add-fill"]`, `[data-action="remove-fill"]`, `#fill-template`, `fills[n][side\|quantity\|price\|fees\|executed_at]` |
| A4 | Live summary | MVP | Recalculate on every input. Use the same math as the database (see the note after this table). | Reads `futures_specs` once for futures multipliers. | `[data-summary="quantity\|avg-entry\|avg-exit\|gross-pnl\|fees\|net-pnl\|r-multiple\|hold-time\|status"]` |
| A5 | Tags | MVP | Enter or comma adds a chip, Backspace in an empty input removes the last chip, and clicking a suggestion adds it. New names are created when the trade is saved. | `tags`, `trade_tags` | `[data-chip-input]`, `#tag-input`, `[data-tag-suggestions]` |
| A6 | Lists | MVP | Checkboxes for the user's lists (up to 2). The limit is enforced when a list is *created*, so nothing to check here. | `trade_lists`, `trade_list_items` | `name="trade_list_ids[]"`, `[data-list-choices]` |
| A7 | Validation | MVP | Check the rules listed after this table before sending anything. Mark bad fields with `aria-invalid="true"` (already styled) and put a summary in the form alert. | | `[data-form-alert]` |
| A8 | Save | MVP | Saves in a fixed order (see "The save sequence" below). Plain **Save trade** goes to `trades.html?saved=1`. **Save and add another** resets the form but keeps the market, account and date. | All of the above | `#trade-form`, submit buttons (`name="intent"`, `value="save-and-new"` on the second) |
| A9 | Screenshots | MVP | Drag and drop or browse. Show thumbnails, allow removing them before save, and reject files over 10 MB or that aren't images. Upload after the trade is created. | Storage bucket `trade-attachments` at path `<user id>/<trade id>/<uuid>.<ext>`, then a row in `trade_attachments` | `[data-dropzone]`, `#screenshots` |
| A10 | Edit an existing trade | MVP | `add-trade.html?id=<trade id>` loads the trade and pre-fills everything. Set the title and breadcrumb to "Edit trade". Saving updates instead of inserting (see the note after this table). | Same tables | `[data-form-title]`, `[data-form-crumb]` |
| A11 | Unsaved-changes warning | Later | `beforeunload` prompt when the form is dirty. | | |
| A12 | Create a setup or list inline | Later | "New setup…" option in the select. "New list" link, hidden when the list limit is reached. | `setups`, `trade_lists` | |
| A13 | Templates / defaults | Later | Remember the last market, account and fee per contract. | `profiles.preferences` | |

**A4 summary math.** This matches `recalculate_trade()`:

- **Opening side:** buy for long, sell for short.
- **Avg entry and avg exit:** quantity-weighted average prices of the opening fills and the closing fills.
- **Gross P&L:** `min(open qty, close qty) × (exit − entry) × multiplier × (+1 long / −1 short)`.
- **Multiplier:**
  - Stock and crypto use 1.
  - Options use 100.
  - Futures use `futures_specs.multiplier` for the root symbol (`ES` from `ESZ6`).
- **Fees:** the sum of all fill fees.
- **Net P&L:** gross minus fees.
- **Status:** "Closed" once close qty ≥ open qty.
- **R-multiple:** net ÷ planned risk.
- **Hold time:** last fill time − first fill time.
- **Precedence:** the saved numbers come from the database. This preview is only a guide.

**A7 validation rules:**

- **Instrument:**
  - Symbol is required.
  - Options need a type, a strike above 0 and an expiration date.
- **Fills:**
  - At least one fill.
  - Each fill needs a quantity above 0, a price of 0 or more, and a date and time.
- **Plan and rating:**
  - Planned risk, if filled in, must be above 0.
  - Rating must be 1–5.
- **Warning only:** close quantity is more than open quantity. Allow saving, because the database ignores the extra quantity.

**A10 edit-mode saving:**

- **Trade:** `update` the editable trade columns.
- **Fills:**
  - Delete the ones the user removed.
  - Update the ones that changed.
  - Insert the new ones.
- **Tags and lists:** replace the trade's `trade_tags` and `trade_list_items`.

### The save sequence (A8)

Supabase JS doesn't do transactions, so save in this order. If any step after 2 fails, delete the new trade. The delete cascades to its fills, tags, lists and attachments, so nothing is left half-saved.

1. **Instrument:**

   ```js
   rpc('get_or_create_instrument', {
     p_asset_class, p_symbol,
     p_option_type, p_strike, p_expiration_date  // options only
   })
   ```

   Returns `instrument_id`. It normalizes options to OCC symbols and looks up futures multipliers, so never insert into `instruments` directly.
2. **Trade:**

   ```js
   insert('trades', {
     instrument_id, direction, broker_account_id, setup_id,
     planned_risk, stop_price, target_price, rating, notes,
     source: 'manual'
   }).select('id')
   ```

   Only these columns are writable. `asset_class`, `status` and all the calculated columns are set by the database.
3. **Fills:**

   ```js
   insert('executions', fills.map(f => ({
     trade_id, side, quantity, price, fees,
     executed_at: new Date(localValue).toISOString()
   })))
   ```

   The trigger recalculates the trade once for the whole batch.
4. **Tags:**
   - Look up the user's existing tags by name. The unique index is on `lower(name)`, so compare case-insensitively.
   - Insert the missing ones.
   - Insert `trade_tags` rows.
5. **Lists:** insert `trade_list_items` rows `{ trade_list_id, trade_id }`.
6. **Screenshots:**
   - Upload each file to `trade-attachments`.
   - Insert `trade_attachments` with `{ trade_id, storage_path, file_name, mime_type, size_bytes }`.

`user_id` is filled in by the database (`default auth.uid()`). Don't send it.

> **Later improvement:** move steps 1–5 into one `create_manual_trade(jsonb)` RPC so the save is atomic and is a single request. Worth doing before imports, which reuse the same path.

---

## 2. Trade Log (`app/trades.html`)

**What it shows:** every trade across all accounts.

**What the user can do:**

- Switch between markets with the tabs.
- Filter, search and sort.
- Select rows to delete, add to a list, or tag.

**Where the data comes from:** the `trade_log` view (added in this PR). It's one flat row per trade, with `symbol`, `setup_name`, `tag_names` and `trade_list_ids` already joined in. Every filter and sort below is a plain `supabase.from('trade_log')` call with no embedded selects. It respects RLS like the tables do.

| # | Feature | Priority | What it does | Data | Hooks in the HTML |
| --- | --- | --- | --- | --- | --- |
| L1 | URL state | MVP | Every filter, the sort, the page and the page size live in the query string: `?market=option&list=…&account=…&setup=…&status=…&from=…&to=…&q=…&sort=trade_date&dir=desc&page=2&size=25`. Read it on load, write it with `history.replaceState` on change. Refresh, back and shared links all work. | | Tabs are already links with `?market=` |
| L2 | Load filter options | MVP | Fill the List, Account and Setup selects. Same queries as A1. | `trade_lists`, `broker_accounts`, `setups` | `#filter-list` (`trade_list_id`), `#filter-account` (`broker_account_id`), `#filter-setup` (`setup_id`) |
| L3 | Fetch and render rows | MVP | Query the view with the current filters, sort and range (see the code after this table). Clone `#trade-row-template` for each row and fill the `[data-field]` slots with the G6 formatters. | `trade_log` | `[data-trade-rows]`, `#trade-row-template`, `[data-field]`, `[data-trade-id]` |
| L4 | Market tabs | MVP | Mark the active tab with `aria-current="page"`. Counts come from one `head: true, count: 'exact'` query per market, using the other active filters. | `trade_log` | `[data-market-tab="all\|stock\|option\|future\|crypto"]`, `[data-market-count]` |
| L5 | Filters | MVP | The form submits to the URL (L1). Clear resets everything except the market. | (see the filter map after this table) | `#trade-filters`, `name="q\|trade_list_id\|broker_account_id\|setup_id\|status\|from\|to"` |
| L6 | Totals strip | MVP | Trades shows the `count` from the L3 query. Net P&L, win rate, profit factor and fees come from `rpc('get_trade_stats', { p_from, p_to, p_asset_class, p_trade_list_id, p_broker_account_id })`. | `get_trade_stats` | `[data-total="trade-count\|net-pnl\|win-rate\|profit-factor\|fees"]` |
| L7 | Sorting | MVP | Clicking a header sorts that column descending. Clicking it again flips the direction. Set `aria-sort` on the `th` (the CSS rotates the arrow). Only one sort at a time. | `trade_log` columns | `[data-sort="trade_date\|symbol\|net_pnl\|r_multiple"]` |
| L8 | Pagination | MVP | Page size 25/50/100. Show "Showing 26–50 of 144 trades". Draw page links (first, last, current ±1, with ellipses) and disable prev/next at the ends with `aria-disabled`. | `count` from L3 | `[data-pagination]`, `[data-page-summary]`, `[data-page-list]`, `[data-page="prev\|next\|<n>"]`, `name="page_size"` |
| L9 | Row selection | MVP | Select-all toggles the visible rows and goes indeterminate when only some are checked. The bulk bar shows when 1+ rows are selected. | | `[data-select-all]`, `name="trade_ids[]"`, `[data-bulk-bar]`, `[data-selected-count]` |
| L10 | Bulk delete | MVP | Confirm first ("Delete 3 trades? This can't be undone."), then delete the selected trades. Fills, tags, list items and attachment rows cascade. Also remove the files from storage. | `trades`, Storage | `[data-action="delete-trades"]` |
| L11 | Bulk add to list / tag | MVP | Pick a list, or type a tag, then insert one row per selected trade. Ignore rows that already exist (upsert). | `trade_list_items`, `tags`, `trade_tags` | `[data-action="add-to-list"]`, `[data-action="add-tag"]` |
| L12 | Empty states | MVP | Two cases share `[data-empty-state]`: **no trades yet** (first visit, show the Add trade / Import buttons) and **no results** (filters too narrow, show "Clear filters"). Change the title, text and buttons for each. Hide the table and pagination in both. | | `[data-empty-state]` |
| L13 | Loading and errors | MVP | Set `aria-busy="true"` on the table while fetching. On error, show the message in the page alert. | | `[data-page-alert]` (add `alert--error`) |
| L14 | Saved message | MVP | After Add Trade redirects with `?saved=1`, show "Trade saved" in the page alert, then remove the param from the URL. | | `[data-page-alert]` |
| L15 | Open a trade | MVP | The symbol links to `add-trade.html?id=<id>` (edit) until the trade detail page exists. | | `a[data-field="symbol"]` |
| L16 | Trade detail page | Later | Fills, chart screenshots, journal notes, edit and delete. Replaces L15's link target. | | |
| L17 | CSV export, column picker, saved filters | Later | | | |

**L3 query:**

```js
supabase.from('trade_log')
  .select('*', { count: 'exact' })
  .order(sort, { ascending, nullsFirst: false })
  .range(start, end)
```

**L5 filter map:**

| Filter | Query call |
| --- | --- |
| Market | `.eq('asset_class', …)` |
| List | `.contains('trade_list_ids', [id])` |
| Account | `.eq('broker_account_id', …)` |
| Setup | `.eq('setup_id', …)` |
| Status | `.eq('status', 'open' \| 'closed')` |
| From | `.gte('trade_date', from)` |
| To | `.lt('trade_date', dayAfter(to))` |
| Search | `.ilike('search_text', '%' + q.toLowerCase() + '%')` |

Debounce the search box by about 300 ms.

**L6 caveats:**

- The stats count closed trades only.
- The setup, status and search filters don't apply to them.
- Label the strip "Closed trades" or extend the RPC later.

**Things to know when building the trade log**

- **Dates:** `trade_date` is the close time for closed trades and the open time for open ones. The Date column shows it, and sorting and the From/To filters use it. Convert From/To to the user's time zone (`profiles.timezone`) before querying.
- **P&L classes:**
  - Net P&L gets `text-gain` or `text-loss`.
  - Side gets `side--long` or `side--short`.
  - The status badge gets `badge--primary` when open.
- **Open trades** have no exit, P&L or R. Show `–`, the same as the sample row.
- **Mobile:** the table already becomes cards under 760px. JS doesn't need to do anything, as long as each `td` keeps its `data-label`.

---

## 3. Suggested build order

Each step can be tested in the browser on its own.

**Sprint 3: groundwork and Add Trade**

1. G1–G4: Supabase client, wire up the auth pages, auth guard, log out.
2. A1: load accounts, setups, tags and lists into the form.
3. A3: add and remove fill rows.
4. A7 + A8 (steps 1–3 only): save a **stock** trade with fills. Check the P&L in the Supabase table editor.
5. A2: options, futures and crypto saving. Test an option and an ES future, since those multipliers are where bugs show up.
6. A4: live summary.
7. A5, A6, A8 steps 4–5: tags and lists.
8. A9: screenshots.
9. "Save and add another".

**Sprint 4: Trade Log and editing**

1. G5, G6: account menu and formatters.
2. L3: render real rows from `trade_log` (no filters yet).
3. L12, L13: empty and error states. Test with a brand new account.
4. L1, L4, L5: URL state, tabs and filters.
5. L7, L8: sorting and pagination. Add 60+ trades to test this, ideally through a quick seed script.
6. L6: totals strip.
7. L14, L15: saved message and link to edit.
8. A10: edit an existing trade.
9. L9–L11: selection and bulk actions.

### Done means

- It works signed in as a new user with zero trades, and as a user with 100+.
- It works at 390px wide and on desktop, in light and night mode.
- There are no console errors, and a failed request shows a message instead of failing silently.
- Another user can't see or change the data. Check it with a second test account.

---

## Common errors to handle

| Error | Cause | Show the user |
| --- | --- | --- |
| `22023 Symbol is required` / `Options need…` | Missing instrument fields | The message, next to the field |
| `P0001 Your plan allows up to 2 trade lists…` | Creating a third list | "You can have 2 lists on the current plan." |
| `23505` on `tags` / `trade_lists` | Name already exists (any case) | "You already have a tag/list with that name." |
| `42501` or an empty result when signed out | Session expired | Redirect to login with `next` |
