---
name: Heisenbudget
description: A calm bench instrument for personal money. Ruled readouts, tick scales, two charts (a spectrum and a trace), hairlines instead of shadows.
colors:
  ink-ground: "#070A09"
  ink-panel: "#0D1210"
  ink-panel-high: "#131A17"
  ink-hairline: "#26302B"
  ink-outline: "#3A4742"
  ink-text: "#E6EDE9"
  ink-dim: "#8A9892"
  ink-faint: "#56625C"
  ink-received: "#3EE08F"
  ink-spent: "#FFB547"
  ink-error: "#FF6B57"
  ink-on-accent: "#04120B"
  bench-ground: "#F4F6F5"
  bench-panel: "#FFFFFF"
  bench-panel-high: "#EBEFED"
  bench-hairline: "#D5DCD8"
  bench-outline: "#B3BDB8"
  bench-text: "#0C1411"
  bench-dim: "#55635C"
  bench-faint: "#7C8983"
  bench-received: "#0B7A48"
  bench-spent: "#9A5600"
  bench-spent-fill: "#C47600"
  bench-error: "#C2321F"
  bench-on-accent: "#FFFFFF"
  accent-assay-ink: "#2FD6C0"
  accent-assay-bench: "#087569"
  accent-ice-ink: "#5CC8FF"
  accent-ice-bench: "#0B6BA8"
  accent-violet-ink: "#B69CFF"
  accent-violet-bench: "#6A43D6"
  accent-rose-ink: "#FF8FB1"
  accent-rose-bench: "#C2275F"
  accent-graphite-ink: "#D7DEDA"
  accent-graphite-bench: "#2A3330"
typography:
  readout:
    fontFamily: "Geist Mono"
    fontSize: "44sp"
    fontWeight: 600
    letterSpacing: "-1"
    fontFeature: "tabular figures"
  amount-entry:
    fontFamily: "Geist Mono"
    fontSize: "32sp"
    fontWeight: 500
    fontFeature: "tabular figures"
  ledger-value:
    fontFamily: "Geist Mono"
    fontSize: "17sp"
    fontWeight: 500
    fontFeature: "tabular figures"
  row-amount:
    fontFamily: "Geist Mono"
    fontSize: "16sp"
    fontWeight: 500
    fontFeature: "tabular figures"
  title-large:
    fontFamily: "Geist"
    fontSize: "20sp"
    fontWeight: 600
  title-medium:
    fontFamily: "Geist"
    fontSize: "16sp"
    fontWeight: 600
  title-small:
    fontFamily: "Geist"
    fontSize: "14sp"
    fontWeight: 600
  body-large:
    fontFamily: "Geist"
    fontSize: "16sp"
    fontWeight: 400
    lineHeight: 1.35
  body-medium:
    fontFamily: "Geist"
    fontSize: "15sp"
    fontWeight: 400
    lineHeight: 1.35
  body-small:
    fontFamily: "Geist"
    fontSize: "13sp"
    fontWeight: 400
    lineHeight: 1.3
  label-large:
    fontFamily: "Geist"
    fontSize: "14sp"
    fontWeight: 600
  label:
    fontFamily: "Geist"
    fontSize: "12sp"
    fontWeight: 600
    letterSpacing: "0.9"
  label-small:
    fontFamily: "Geist"
    fontSize: "12sp"
    fontWeight: 500
    letterSpacing: "0.6"
rounded:
  chip: "8dp"
  input: "10dp"
  panel: "12dp"
  dialog: "16dp"
  sheet: "20dp"
spacing:
  xs: "4dp"
  s: "8dp"
  m: "12dp"
  l: "16dp"
  xl: "24dp"
  xxl: "32dp"
components:
  add-key:
    backgroundColor: "{colors.accent-assay-ink}"
    textColor: "{colors.ink-on-accent}"
    typography: "{typography.label-large}"
    rounded: "{rounded.input}"
  button-filled:
    backgroundColor: "{colors.accent-assay-ink}"
    textColor: "{colors.ink-on-accent}"
    typography: "{typography.label-large}"
    rounded: "{rounded.input}"
    height: "52dp"
  button-outlined:
    textColor: "{colors.ink-text}"
    typography: "{typography.label-large}"
    rounded: "{rounded.input}"
    height: "48dp"
  button-text:
    textColor: "{colors.accent-assay-ink}"
    typography: "{typography.label-large}"
    height: "48dp"
  chip:
    textColor: "{colors.ink-text}"
    rounded: "{rounded.chip}"
  sheet:
    backgroundColor: "{colors.ink-panel}"
    rounded: "{rounded.sheet}"
  dialog:
    backgroundColor: "{colors.ink-panel}"
    rounded: "{rounded.dialog}"
  menu:
    backgroundColor: "{colors.ink-panel-high}"
    rounded: "{rounded.input}"
  navigation-bar:
    backgroundColor: "{colors.ink-ground}"
    height: "68dp"
  category-tile:
    rounded: "{rounded.chip}"
    size: "36dp"
  period-select:
    rounded: "{rounded.input}"
    height: "48dp"
  day-header:
    backgroundColor: "{colors.ink-panel}"
    height: "40dp"
  ledger-row:
    textColor: "{colors.ink-text}"
    typography: "{typography.ledger-value}"
    height: "40dp"
---

# Design System: Heisenbudget

## Overview

**Creative North Star: "The Bench Instrument"**

Money is a measurement. The app reads like a small, calm piece of lab equipment: ruled readouts, a tick scale for the period, a spectrum chart and a trace of the months, and nothing that shouts. It is dark first. The default Ink palette is a near-black ground with a faint green cast, and the Bench palette is its light sibling. Depth comes from tonal panels one or two steps off the ground and from 1dp hairlines. There are no shadows anywhere in the build.

Colour carries meaning, so it is rationed. Two fixed channels, Received (green) and Spent (amber), mark money events and never change with the accent. One switchable accent (default Assay teal) colours chrome only: the add key, selected states, switches, the today tick, chart focus, caret. Numbers are always Geist Mono with tabular figures so digits never shift. Layout is left aligned, dense but unhurried, built for one-handed sessions in dim light.

An optional Lab flavor layer (on by default) swaps a few strings for instrument wording. The look is identical with it off.

**Key Characteristics:**
- Ink and Bench palettes, tonal panels plus 1dp hairlines, zero shadows.
- Two money channels (Received, Spent) independent of five selectable accents.
- Geist Mono tabular for every number; UI text in a user-chosen face.
- Small radii (8 to 20dp), nothing is a pill; the add key is a 10dp rounded rectangle.
- Instrument furniture is local: graticule only inside the two charts, tick ruler only on the period control, dotted leaders only on Home's three summary rows.

## Colors

A green-cast ink ground with bone-white text, one amber, one green, and a rationed accent.

### Primary
- **Assay Teal** (#2FD6C0 on Ink, #087569 on Bench): the default accent. Chrome only. It was moved away from green so it stays visibly distinct from the Received channel.
- **Ice** (#5CC8FF / #0B6BA8), **Violet** (#B69CFF / #6A43D6), **Rose** (#FF8FB1 / #C2275F), **Graphite** (#D7DEDA / #2A3330): the four alternative accents, ink value then bench value. Amber is deliberately not offered; it is Spent.

### Secondary
- **Received Green** (#3EE08F Ink, #0B7A48 Bench): money in. Row amounts, the RECEIVED ledger row and its sign.
- **Spent Amber** (#FFB547 Ink, #9A5600 Bench): money out, negative balance, warnings, chart peaks. Peaks use the non-text fill value, which on Bench is a touch brighter (#C47600) and equal to the text value on Ink.

### Neutral
- **Ink Ground** (#070A09): screen background, app bar, navigation bar.
- **Ink Panel** (#0D1210) and **Ink Panel High** (#131A17): sheets, dialogs, pinned day headers; menus, snackbars and selected or raised states.
- **Ink Hairline** (#26302B): every 1dp rule, divider and chip border. **Ink Outline** (#3A4742): input and outlined-button borders.
- **Bone Text** (#E6EDE9), **Dim** (#8A9892) for secondary text, **Faint** (#56625C) for non-text marks only (ticks, leader dots, tile borders, empty-state icons).
- **Error Coral** (#FF6B57 Ink, #C2321F Bench).
- **Bench Ground** (#F4F6F5), Panel (#FFFFFF), Panel High (#EBEFED), Hairline (#D5DCD8), Outline (#B3BDB8), Text (#0C1411), Dim (#55635C), Faint (#7C8983). On-accent is #04120B on Ink and #FFFFFF on Bench.

### Named Rules
**The Two Channels Rule.** Received is green and Spent is amber in every theme and under every accent. The accent never borrows either hue, and amber is never an accent.

**The Sign Plus Colour Rule.** A money event is never told apart by colour alone: amounts carry a visible + or - and rows carry an arrow glyph.

**The Faint Is Not Text Rule.** The faint grey is for marks. Words use text or dim.

## Typography

**UI Font:** Geist, selectable among Inter, Atkinson Hyperlegible, and System (the phone's own face, which also covers scripts the others lack). All bundled, none downloaded.
**Number Font:** Geist Mono (Regular, Medium, SemiBold) with tabular figures, regardless of the UI font choice.

**Character:** A plain grotesque for words, a mono for measurements. The contrast between the two is the whole typographic idea.

### Hierarchy
- **Readout** (Geist Mono 600, 44sp, letter-spacing -1): the Home balance, left aligned, negative values in Spent amber. Scales down with a FittedBox, never wraps.
- **Amount entry** (Geist Mono 500, 32sp): the Add sheet amount and the opening-balance field, text scale capped at 130%.
- **Ledger value** (Geist Mono 500, 17sp): right-aligned values in the RECEIVED / SPENT / NET rows. Row amount 16sp, chart readout amount 15sp, day-header net 14sp, range text 13sp (400), chart percentages 12sp, PURITY 12.5sp.
- **Title** (Geist 600; 20, 16, 14sp): app bar and dialog titles, sheet heads.
- **Body** (Geist 400; 16, 15, 13sp, line height 1.35 to 1.3): row titles, notes; body-small is dim.
- **Label** (Geist 600, 12sp, tracking 0.9, dim, uppercase by caller): section labels, BALANCE caption, ledger row labels, app name (tracking 2.2). Label-small (500, 12sp, tracking 0.6) for navigation and chart category names. 12sp is the floor.
- **Button label** (Geist 600, 14sp): all buttons and chips; the add key adds tracking 1.1.

### Named Rules
**The Tabular Rule.** Every digit that stands for money, a date range, a percentage or a count is in Geist Mono with tabular figures. Words are never in mono.

**The 12sp Floor Rule.** Nothing is set below 12sp. All sizes are sp and follow the system font size.

## Layout

A single left-aligned column on a 4dp grid. Gap tokens: xs 4, s 8, m 12, l 16, xl 24, xxl 32. Screens use 20dp side padding; Home scrolls with 120dp bottom padding to clear the add key. Section breaks are 24dp (Gap.xl), label to content 12dp. Ledger summary rows are 40dp display-only rows; every tappable thing is at least 48dp (text buttons 48x48, period select 48dp, accent swatches 48dp targets around 36dp discs, step arrows are standard icon buttons). Rows hold their height and scale their content down together (FittedBox) rather than overflow.

Text scaling to 200% is a strategy, not a hope. Body text and rows reflow and wrap. Big readouts (balance, amount entry, chart labels) are capped at 130% text scale and shrink to fit. Above 130% the wide add key collapses to an icon-only key, and the theme-mode segmented bar becomes wrapping chips. Navigation is a three-tab bar (Home, History, Settings), 68dp, hairline above.

## Elevation & Depth

Flat. There are no shadows, no glow and no surface tint: elevation is 0 on every component and surfaceTint is transparent. Depth is conveyed in two ways only: tonal steps (ground, panel, panel-high) and 1dp hairlines. Sheets and dialogs sit on Panel with a hairline border; menus, snackbars and tooltips sit on Panel High with a hairline. The pinned History day header is a 40dp Panel strip with a hairline under it, so rows scroll beneath it by tone, not by shadow.

### Named Rules
**The Hairline Rule.** Separate with a 1dp hairline or a tonal step. Never with a shadow.

## Shapes

Small, instrument-panel corners. Radii: chip 8dp (chips, category tiles, tooltips, icon-picker cells, chart peak tap area), input 10dp (fields, buttons, add key, period select, nav indicator, menus, snackbar), panel 12dp (empty-state frame, welcome panel), dialog 16dp, sheet 20dp (top corners only). Chart peaks have 4dp top corners and are 24dp wide. Icons are outlined Material icons held in outlined squares (36dp category tile, 1dp border, faint for live and hairline for archived). The only circles are the accent swatches.

## Components

### Buttons
- **Shape:** 10dp rounded rectangle. No pills.
- **Filled:** accent fill, on-accent text, 52dp minimum height, elevation 0.
- **Outlined:** outline-colour border, text colour label, 48dp minimum height. **Text:** accent label, 48x48 minimum.
- **Add key:** extended accent key bottom right, label LOG (Lab on) or ADD (Lab off) with a plus icon, 10dp radius, no elevation; icon-only above 130% text scale. Tooltip "Add transaction".
- **Pressed:** accent splash at 10% and highlight at 6%.

### Chips
Transparent with a hairline border, 8dp radius, 14sp medium label. Selected: accent-tinted container (accent at 16% over Panel), accent label and check. Used for History period filters, font choice, and large-text theme mode.

### Ledger row (dotted leader)
Signature. Label (12sp tracked, dim) at left, a row of faint 1.6dp-diameter dots 4dp apart on the baseline, value in 17sp mono at right. An optional 16dp arrow glyph precedes the label (down for Received, up for Spent, equals for Net). Merged into one screen-reader phrase. Used only for Home's RECEIVED / SPENT / NET.

### Section label
Uppercase 12sp tracked dim label with a hairline running out to the right and an optional trailing text button. Marked as a header for screen readers.

### Settings page
A short ListView in four SectionLabel groups (Appearance and numbers, Manage, Your data, About). Each row is a ListTile with an outlined leading icon, the title, a dim live summary (up to three lines) and a chevron when it opens a page. Appearance and Money & dates are pushed pages of the same pattern: dim subheads, then the controls unchanged. The About group is a single row that opens the About screen (name, version, a short description, the privacy-policy address as selectable mono text with a Copy link button, and how the data is kept). Erase everything is drawn in the error colour. A backup older than 30 days has its line in full-strength semibold text and says "N days ago": words and weight, never the Spent amber, which stays a money colour. Section labels wrap at large text.

### Tick ruler
16dp tall, under the period control. One tick per day (per week above 62 days): past ticks dim, future ticks faint, major ticks every 7th (every 4th when weekly), today a 14dp accent tick 2dp wide. It fills in left to right over 420ms once per period change.

### Counting readout
The balance counts to its new value in 350ms (ease-out cubic). Screen readers hear only the final value.

### Spectrum chart
Top categories (up to five plus a Rest bar in the render) as 24dp amber peaks over a graticule of four hairlines and a stronger baseline, 152dp tall; percentage in 12sp mono above each peak, icon and name below. Tap focuses one peak: others dim to 32% and a readout line shows name, share and amount. Each peak is a labelled button. Empty state: a flat baseline with one line of text. Peaks rise left to right over 700ms. Chart labels are capped at 130% text scale.

A focused peak also offers **See transactions** (History on that category and the chart's period; for the Rest peak, all the categories folded into it) and, for a single category, **See trend**. Both are 48dp text buttons under the readout.

### Trace chart
Months side by side, same vocabulary as the spectrum: peaks with 3dp top corners over the graticule (four hairlines and a baseline), 152dp tall, month name in 12sp under each peak (it shrinks, never wraps). Money in and out: a pair per month, Received (green, 9dp) beside Spent (amber, 9dp); a single category: one amber peak (18dp). The month still going is drawn at about 60% so a part-month is never read as a whole one. Tap focuses a month: the others dim to 32% and a readout under the chart gives its title in caps ("SEPTEMBER 2026", "· SO FAR" while it runs), then Received, Spent, Net and the share kept as labelled mono figures that wrap at large text. Peaks rise left to right over 700ms (skipped with reduce-motion). Every month is a labelled button ("September 2026, received $2,000.00, spent $300.00"). **Every trace has a "Show as a list" toggle** that swaps the chart for the same months as text, newest first; a trace with nothing logged is the flat baseline and one line of words. Chart labels are capped at 130% text scale.

### App logo
The flask on its own light ground (`assets/logos/logo.png`, 43 KB, the one image the app bundles), shown as a rounded square (radius 22% of its size) cropped to the launcher icon's proportions: 72dp beside the name and version on About, and 72dp on the first Welcome page. The ground is part of the image because the glass outline is near-black and would vanish on the dark Ink ground, so the logo is always a light tile, in light mode too. It is a labelled image ("Heisenbudget logo") for screen readers.

### Home notice slot
The top of Home holds at most one notice card, so cards never stack: the month-end report announcement in a budget month's first seven days (it takes priority), else the backup reminder. A card is a panel (panel fill, 1dp hairline, panel radius) with a title, one or two lines, and 48dp text buttons in an OverflowBar. Nothing is drawn when there is no notice.

### Home glances
A short look at something that has a page of its own: a section label (with "See all" at the right, 48dp), then a few lines. The glance never grows: detail lives on the page. `HomeGlance` is the shared widget; Home shows none today (the Insights tab took the trend glance), so a new one has to earn its place on a screen that is already a readout. Glances ignore the period selector and say so in their label.

### Insights tab
The third tab (Home, Budgets, Insights, History, Settings), built the first time it is opened and kept after that; it has no back arrow. The chart's **See trend** on Home switches to it with that category chosen. It opens with the month-end report card when one is due (the same card Home shows; dismissing it clears both). A 6 or 12 months choice (chips), then blocks under section labels: *Money in and out* (trace chart and its list toggle), the share kept by month (plain rows, no chart), *A category over time* (chips for the five biggest, plus the one asked for, and a trace for it; "None" shows a hint, not a copy of the first chart), *What moved* (the last finished month against the three before: up to three rises and three falls with arrow, sign and amount, never colour alone) and *This month so far* (biggest expense, busiest day, average a day, days with no spending, longest run). Rows are 48dp minimum with a hairline; values shrink with the label. Months are budget months (the "month starts on" setting), the same as budgets. With only one month of history it says so instead of showing empty comparisons. At the end, *Lab reports* ("Monthly reviews" with Lab flavor off) lists the last twelve finished months that have something in them, as plain rows (month, share kept, net) that open the report.

### Month-end report
Pushed over the app, from the Home or Insights notice card or the Reports list on Insights. One finished budget month on a plain scrolling page, in rows with hairlines and no chart: the month and its dates, then *The month* (Received, Spent, Net and the share kept, each with how it compares with the month before in words, "$100.00 less than August"), *Budgets* (one row per budget that had a period end in the month: spent of limit and "Over by" or "under", with an *Adjust* or *Copy forward* text button), *What moved* (the same mover rows as Trends), *Biggest expenses* (five rows that open the transaction), *How it ran* (average a day, busiest day, days with no spending, longest run) and *Next* (at most three actions: a limit for a big category that has no budget, a backup if there is no recent one). A section with nothing to say is left out. The report never shows goals until there are goals. Opening it, or dismissing its card, counts as read (phone-only `report_seen_month`).

### Transaction row
Category tile at left, then the first line in 16sp medium: the category name, or "Title · Category" when the transaction has a title (the title is never a replacement for the category). Under it the date and note in dim (Home shows the date), amount in 16sp mono at right coloured by channel with explicit sign, closed by a hairline. Archived categories are marked "(archived)" and drawn in faint.

A row made by a repeating rule carries a small 14dp repeat icon (dim, labelled "Repeating") ahead of its date and note.

### Coming up row
Home shows up to three repeating transactions due in the next 7 days under a COMING UP label, between the chart and Recent. Same layout as a transaction row (category tile, name, date and "in N days" or "tomorrow"), but the amount is **dim, not green or amber**: nothing has happened yet, and Received and Spent colours are reserved for money that has moved. Hidden when there are none. Never part of a total.

### Delta line ("vs last month")
One line of 12sp mono, dim, directly under the Received and Spent ledger rows: a triangle (▲ ▼, or = for "about the same"), the change (whole percent, or the amount when the earlier total was zero, capped at 999%+) and "vs" with the compared dates ("vs Sep" for a whole month, otherwise "vs Sep 1–25"). Dim text, never the green or amber channels, and not the arrows used by the ledger rows; the meaning is in the glyph and the words. Scales down to fit at large text. Spoken as a full sentence.

### Launcher shortcut icons
Three 192px icons for the long-press menu: an amber up arrow (Add expense), a green down arrow (Add income) and a teal bolt (the favorite), each on a dark disc on Android; black template silhouettes on iOS, which tints them. They echo the ledger arrows and the accent.

### Search field and highlight
A search icon in the History app bar reveals a text field above Filter and Sort (hint "Search notes, categories, amounts", clear button). Matches in the category name and note are bold on a soft accent tint (22% accent), never colour alone. A dim line under the controls reads "12 results · net -$84.20". The control block scrolls when it needs more than half the screen.

### Row menu and Quick add
Pressing and holding a transaction opens a full-height-capable bottom sheet of 48dp rows: Edit, Duplicate, Save as favorite, Delete (error colour). Favorites are chips in a one-line Quick add row at the top of the Add sheet (scrolls sideways): panel fill, hairline border, 8dp radius, 48dp tall, category icon, name in 14sp medium and the amount in 13sp dim mono. Absent when there are none, and on the Edit sheet or a sheet opened already filled in. Tap logs and closes the sheet; long-press fills the form. Home has no Quick add.

### Repeat sheet
A bottom sheet with wrapping choice chips (Does not repeat, Weekly, Monthly, Yearly, Custom), a number field and unit chips for Custom, a dim plain-language summary ("Monthly on the 1st") and an Ends row. It scrolls, so it holds at 200% text.

### Category tile and icon picker
36dp outlined square, 8dp radius, icon at 55% of tile. The icon picker is a grid of icon buttons with 8dp radius; the selected one takes the accent-tinted container.

### Period selector and chips
An outlined 10dp dropdown button (48dp, label plus drop-arrow), previous and next arrows, the tick ruler, and the resolved range in 13sp mono dim. The menu lists This week, This month, Week 1 to N, Custom range. History uses wrapping period chips instead.

### Appearance pickers
Theme mode: three-segment control (10dp, outlined, selected tinted), chips at large text. Accent: five 36dp discs in 48dp targets, chosen one ringed in text colour with a check, spoken name "<Name> accent". Font: chips, each label drawn in its own face. Currency: searchable dropdown menu.

### Sheets, dialogs, menus
Sheet: Panel, 20dp top radius, hairline, drag handle in faint. Dialog: Panel, 16dp radius, hairline. Menus and snackbars: Panel High, 10dp, hairline, floating snackbar with accent action. Inputs: 10dp outline, accent 1.5dp when focused, error colour on error, 14dp padding.

### Budgets
The second tab (Home, Budgets, History, Settings): the **current period of every budget**, worst first, each a panel gauge: category tile and name, a dim period line ("Monthly · October 2026", "Weekly · Oct 12 – Oct 18, 2026", "Just this month · October 2026"), the amounts in 18sp mono ("$120.00 of $200.00"), a 10dp bar, then the words: what is left, "Almost: …" from 80 percent (warning icon, semibold), or "Over by …" (error icon, error colour, error border). The bar is the Spent amber; over the limit it turns the error colour **and** gets diagonal stripes, so colour is never the only signal. Repeating expenses still due show as a lighter segment after the spent part and a dim "Planned" line. Under it, dim: days left and about how much a day. Gauges read as one sentence for screen readers. A history icon in the app bar and a text link under the list jump to History's Budgets side. The editor sheet asks for the limit, the length (chips: Monthly, Custom; Custom adds a number field with a Days/Months dropdown on the same row, 1 to 365 days or 1 to 60 months, and quick picks: 1 week, Quarter (3 months), 1 year, Rest of this year, which is one run of days to Dec 31 and turns the one-time switch on; choosing any other length turns it back off unless the person set it themselves), a "Just this period" switch (off by default: it repeats), the first day of a run of days when one is being created, and offers the average. Home carries a single line (an icon, "2 over budget" or "All within budget", a chevron) that opens the tab; the error icon and bold words show trouble.

### History pill and past budgets
A rounded **Transactions | Budgets** switch (stadium shape, a 4dp-padded panel track with a hairline; the chosen side filled with the accent, label in the on-accent colour) sits directly under the app bar. Filter sits at the left and Sort at the right edge under it, belonging to the chosen side, each side keeping its own. The Budgets side lists finished periods under tonal month headers, as read-only compact gauges whose words are "Under by", "Over by" or "Used it all" (no "Almost", no days left). A period a later change or a stop cut short shows its real dates and ends its period line with "Ended early". The add key and the search icon appear on the Transactions side only.

### Section labels, the History pill and large text
A section label (tracked caps) draws its hairline only when the whole label fits on one line beside it; at large text the label takes the line and wraps between words, never inside one. The History pill's two sides are one line each (48dp tall) and scale their text down rather than breaking a word. Both were found on a 360dp phone at 200% text with the real font, which the widget tests' wide test font does not reproduce: check new headings and pill-like controls on a device.

### Long lists
History reads a page at a time. Near the end of the list (600dp before it) the next page loads on its own; a 24dp progress ring shows while it does, and a **Show more** text button stands in for people who cannot scroll to trigger it. Nothing appears once everything is loaded. The search summary ("40 results · net -$30.00") counts every match, not only the pages loaded.

### Recovery screen
Shown instead of the app when the data cannot be opened (a failed update, a damaged or newer file). A centred column (max 480dp): an error icon, "Heisenbudget could not open your data", "Nothing has been deleted. Choose how to continue.", then a filled **Try again**, an outlined **Restore the copy from before the update (date)** (only when the safety copy exists), an outlined **Restore from a backup file**, and a text **Erase everything and start over** in the error colour. Each destructive choice asks first and says what it does. A collapsed **Details** shows the technical cause. It uses the app's theme and fits at 200% text (the column scrolls).

### Navigation bar
Five destinations (Home, Budgets, Insights, History, Settings). Ground background, 68dp, hairline above, 24dp icons, 12sp labels. Selected: accent icon and label on an accent-tinted 10dp indicator; unselected: dim.

### Empty state
56dp outlined 12dp square with a faint 26dp icon, message in body-medium dim, optional outlined button. Lab wording: "Flat line." leads each empty message.

### Motion
Short and functional: counting 350ms, ruler 420ms, chart rise 700ms, welcome slide 280ms, all ease-out. With the system reduce-motion setting on, every one of them is skipped (zero duration, final state). Save gives a light haptic tick.

### Lab flavor
One switch, on by default, only changes strings (lib/core/copy.dart): chart title Spectrum vs Spending, empty states beginning "Flat line.", and a PURITY readout under the balance (computed from the period, never a fixed value). Visuals are identical either way.

## Do's and Don'ts

### Do:
- **Do** use Gap and Radii constants; build on the 4dp grid.
- **Do** put every number in Geist Mono tabular, and sign every amount with + or - plus its channel colour.
- **Do** keep the accent on chrome only and Received and Spent on money only.
- **Do** separate with hairlines (1dp) and tonal panels, in both Ink and Bench.
- **Do** keep touch targets at 48dp or larger, text at 12sp or larger, and cap big readouts at 130% text scale while letting everything else scale fully.
- **Do** honour reduce-motion on every animation and give each new animation a skip path.
- **Do** keep all wording in Copy so Lab on and off both stay complete.
- **Do** keep launcher artwork free of show imagery (a generic lab flask; origin and terms in extra/ASSET_PROVENANCE.md) and fonts bundled under OFL.

### Don't:
- **Don't** add shadows, glow, surface tint, pill buttons, stat cards or donut charts.
- **Don't** offer amber as an accent or let any accent land near the Received green.
- **Don't** use the faint grey for words.
- **Don't** spread leaders, graticule or tick ruler to other screens: leaders on Home's summary rows, graticule inside the charts, ruler on the period control.
- **Don't** use any show logo, show lettering, or hat-and-glasses silhouette, quote the show, or hard-code a "99.1%" purity figure.
- **Don't** make the Lab flavor change layout or colour.
