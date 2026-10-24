# Legal pages

`privacy.html`, `terms.html` and `contact.html` at the repo root. They are **drafts written as
templates, not legal advice**, and need review by a lawyer before launch. Once reviewed, fill in the
placeholders and delete the `.legal-notice` block at the top of both documents.

## Placeholders

Search for `[` in the three pages. Each one appears in brackets, like `[CONTACT EMAIL]`.

| Placeholder | Where | Notes |
| --- | --- | --- |
| `[COMPANY LEGAL NAME]`, `[ENTITY TYPE]`, `[JURISDICTION]`, `[COUNTRY]` | Privacy, Terms, Contact | e.g. "TradeLab LLC", "a limited liability company", "Delaware" |
| `[MAILING ADDRESS]` | All three | A physical address, required by CCPA/GDPR notices and DMCA |
| `[CONTACT EMAIL]` | All three | Also used for privacy requests, appeals, arbitration notices and opt-outs |
| `[EFFECTIVE DATE]`, `[LAST UPDATED DATE]` | Privacy, Terms | |
| `[GOVERNING STATE/COUNTRY]`, `[COUNTY, STATE]` | Terms §18 | Courts for anything not arbitrated |
| `[ARBITRATION PROVIDER]`, `[ARBITRATION RULES]` | Terms §19 | AAA Consumer Rules or JAMS Streamlined Rules are common |
| `[DMCA AGENT NAME]` | Terms §13 | Register the agent with the US Copyright Office for safe harbor |
| `[PAYMENT PROCESSOR]` | Privacy, Terms | Matches `subscriptions.provider` (defaults to Stripe) |
| `[WEBSITE HOSTING PROVIDER]`, `[EMAIL PROVIDER]`, `[HOSTING REGION]` | Privacy §5 | The Supabase project region, e.g. us-east-1 |
| `[EU REPRESENTATIVE ...]`, `[UK REPRESENTATIVE ...]` | Privacy §10 | Required under Art. 27 GDPR / UK GDPR if there is no office there |
| `[LOG RETENTION]`, `[BACKUP RETENTION]`, `[BILLING RETENTION]`, `[SUPPORT RETENTION]`, `[INACTIVITY PERIOD]` | Privacy §7 | Must match what is actually configured |
| `[RESPONSE TIME]` | Contact | |

## What the documents cover

- **Privacy:** GDPR and UK GDPR (legal bases, rights, transfers, representatives), Swiss FADP,
  CCPA/CPRA (notice at collection table, sensitive data, no sale/share, Shine the Light), the other
  US state comprehensive privacy laws in effect as of 2026 (rights, appeals), Global Privacy
  Control, and COPPA (18+ service, no data from under-13s).
- **Terms:** not-financial-advice and not-a-regulated-adviser disclaimer, accuracy of imports and
  calculations, plans and the trade list limit, auto-renewal terms for paid plans, early access
  features, content license, acceptable use, broker trademark disclaimer, DMCA, disclaimers,
  limitation of liability, indemnity, arbitration with a class action waiver, 30-day opt-out and
  mass-filing batching, and EEA/UK consumer carve-outs.

## Things to check with the lawyer

1. **Original broker files are stored.** The `imports` bucket keeps uploaded files and
   `import_rows.raw` keeps every row, which can include a full account number. The privacy policy
   says so. The landing page's "Private by default" card says "we never store full account
   numbers", which is only true of `broker_accounts`; either strip account numbers on upload or
   soften that line.
2. **Google Fonts.** Pages load Manrope from Google, which sends visitors' IP addresses to Google.
   Some EU courts have found this unlawful without consent. Self-hosting the font in `assets/fonts/`
   removes the issue, and the "Google Fonts" line in Privacy §5 can then go.
3. **Analytics.** The policy says there are no analytics or advertising cookies. If any are added,
   update §6 and add a consent banner for EEA/UK visitors.
4. **Sign in with Google.** Mentioned as optional in Privacy §2. Remove it if it isn't offered.
5. **Data export and account deletion** are promised in both documents. Make sure they exist in
   settings before launch.
6. **Arbitration** must be shown so users clearly agree to it, e.g. a checkbox or "By creating an
   account you agree to the Terms" next to the sign-up button, with a link.
7. **Auto-renewal.** Before paid plans launch, the checkout must show the renewal terms clearly
   and get consent, and cancellation must be possible online (California and FTC rules).

## Contact form

The form is static. See the comment above the `<form>` in `contact.html` for the data attributes
and field names to wire up. The `website` field is a honeypot for spam.
