# Design mockups

Five visual directions explored before building v1. Each has a dashboard and a landing page, and all of them use the same sample trades so they're easy to compare.

Interactive canvas (all ten screens side by side): https://claude.ai/artifact/3uJLVvK8kHcwBuEyc7SL2B

| Direction | Look | Theme file | Status |
| --- | --- | --- | --- |
| A · Terminal | Near-black, lime accent, monospace numbers, dense | `assets/css/themes/terminal.css` | Saved for later |
| **B · Daylight** | Light, indigo accent, spacious, calm | `assets/css/themes/daylight.css` | **Chosen for v1** |
| C · Nightshift | Deep violet, rounded cards, friendly | `assets/css/themes/nightshift.css` | Saved for later |
| D · Ledger | Swiss print style, black ink, signal orange, square corners | `assets/css/themes/ledger.css` | Saved for later |
| E · Harbor | Navy, blue for gains and amber for losses (color-blind safe) | `assets/css/themes/harbor.css` | Saved for later |

## Files

`*.dc.html` are the source files from the design canvas. They use the canvas runtime, so open them on the canvas link above rather than directly in a browser. Treat them as a visual reference.

## Trying another direction

Every theme file defines the same CSS variables. To try a different look on the real site, change the theme `<link>` in a page's `<head>`:

```html
<link rel="stylesheet" href="assets/css/themes/nightshift.css">
```

Colors, fonts, corner radius and shadows change everywhere at once. Layout differences between the mockups (for example A's sidebar or D's ruled tables) would need their own page CSS in a separate branch or repo.
