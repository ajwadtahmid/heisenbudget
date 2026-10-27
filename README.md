# Heisenbudget

A simple personal expense and income tracker for Android and iOS, with a light
chemistry-lab look. It works **100% offline**: no accounts, no internet, no
cloud, no analytics. Everything is stored on the device, and the app has no server
of its own. (Your phone's own backup, Google on Android or iCloud on iPhone, may
keep a copy of the app's data in your account if you have it switched on; see
"Your data and your phone's backup" below.) The app is in English only: dates and
numbers read the same whatever language the phone is set to.

> Not affiliated with or endorsed by any TV show or its owners. The name is a
> pun on a physicist's name; the icon, colors and wording are not taken from
> any show.

## What it does

- Shows your balance and Received / Spent / Net for a period you choose from one
  compact menu: this week, this month, Week 1 to N of a month, or a custom
  date range.
- Adds, edits and deletes income and expenses from a bottom sheet (amount,
  date, category, note).
- History tab: grouped by day, filter by type, category and date (All time,
  this week, this month, last month, custom) and amount range (at least and at
  most), sort, swipe to delete with Undo. "Jump to date" starts a date-sorted
  list from a day you pick (inside the period, if one is set). Filters you use
  often can be saved under a name in the filter sheet and brought back in one
  tap (up to 20; "This month" means the month of the day you use it; they travel
  in a backup).
- Every category has an icon, picked from about 240 built-in Material icons in
  labelled sections with a search box. Change any of them, and pick one when you
  make your own. Archive and restore categories.
- A calm "instrument" look: ruled readouts in tabular mono numbers, a tick
  ruler showing how far through the period you are, and a spectrum chart of
  spending by category (tap a peak for the exact share, then "See
  transactions" opens History on that category and period).
- Appearance settings: light, dark or follow the phone; five accent colours;
  four text fonts (Geist, Inter, Atkinson Hyperlegible, System; numbers always
  Geist Mono); and a Lab flavor switch for the playful wording.
- A short first-run welcome with an optional opening balance.
- Settings is a short page in four groups. Appearance (theme, accent, text
  font, Lab flavor, with a list of what Lab flavor changes) and Money & dates
  (currency from a searchable list including BDT ৳, opening balance, calendar
  weeks or fixed 7-day blocks, and which weekday a week starts on) open their
  own pages and show what is set on the row. Manage holds Categories,
  Repeating transactions and Favorites. Your data holds Back up, Restore,
  Export to CSV and Erase everything. About opens an About screen with the
  app name, version, a short description, the privacy policy address (with a
  Copy link button; the app itself never goes online), how your data is kept
  and the not-affiliated note.

- Optional titles: give a transaction a short name, such as a shop, and its
  row reads "Corner Cafe · Food" over the date, or just "Food" when there is no
  title. Titles are kept by Duplicate, favorites and repeating transactions,
  searched by History search, and included in backups and the CSV.
- Search in History: a search box finds transactions by title, note,
  category or amount (a number matches by prefix, so `4` finds 4.00 to 4.99; several words
  must all match). Matches are highlighted, a results line shows the count and
  net, and it works together with the filters.
- Duplicate and favorites: press and hold a transaction for Edit, Duplicate
  (opens the Add sheet filled in, dated today), Save as favorite and Delete.
  Favorites appear as a Quick add row at the top of the Add sheet: tap one to
  log it dated today and close the sheet (with Undo), or press and hold to fill
  the form with it and change it first. A favorite can leave the amount empty
  to be asked each time. Manage and reorder them under Settings > Quick add.
- Budgets (its own tab): a limit for any expense category and, if you like,
  one for all spending, **per month or a custom length** (1 to 365 days, or
  1 to 60 months; quick picks for a week, a quarter, a year, or the rest of this
  year; monthly and repeating by default, with a "Just this period" switch for
  a one-time budget). The Budgets tab
  shows the current period of each: a bar, what is left (or "Over by"), the
  days left and about how much a day. A bar becomes striped and red when over,
  and "Almost" shows from 80 percent, so it never relies on colour. Changing a
  limit always applies from the current period on and never rewrites earlier
  ones; "Stop this budget" ends it. "Use the average of the last 3 months or
  periods" suggests an amount. A budget that has ended (a one-time one, or one
  you stopped) shows "Copy forward" in History's Budgets: the same amount and
  length, starting with the current period. A budget that ran over in at least
  half of its last few finished periods says "Usually runs over by ..." on its
  card. Repeating transactions still due
  in the period show as a lighter "planned" part. Saving an expense that takes
  a budget over its limit says so, and Home has one line ("2 over budget",
  "All within budget"). A custom length of whole weeks starts on your "Week
  starts on" day, and the budget month can start on any day 1 to 28 (Settings > Money & dates).
- Past budgets: History has a **Transactions | Budgets** switch. The Budgets
  side lists every finished period (monthly, custom, one-time and
  stopped budgets; one a change cut short shows its real dates and "Ended
  early"), newest first, grouped by month, each showing the limit that
  was in force then and "Under by", "Over by" or "Used it all". It has its own
  Filter (period, result, which budget) and Sort. Both sides of History read a page at
  a time and load the next as you scroll (transactions 100 at a time, past budgets
  30), so a long history stays fast; search runs in the database over everything. The Budgets
  tab links to it.
- "vs last month": under Spent and Received on Home, a quiet line such as
  `▼ 12% vs Sep 1–25`. While a period is still going it compares the same days
  (Oct 1–25 with Sep 1–25, not all of September); a finished one compares
  whole against whole. Weeks, week N of a month and custom ranges work too. It
  is hidden when the earlier window had no transactions. It never uses the
  green or amber of the money rows.
- Home-screen shortcuts: press and hold the app icon for Add expense or Add
  income (and one for your first favorite), which open the Add sheet straight
  away. A shortcut chosen while you are typing in an Add sheet is ignored, so
  nothing is lost, and one chosen before the welcome tour is finished waits
  for it. The first favorite's name is visible on the launcher, so Settings > Quick add has a
  switch to turn that shortcut off.
- Repeating transactions: turn on Repeat in the Add sheet (weekly, monthly,
  yearly or every N days, optionally ending on a date) for rent, a salary or a
  subscription. The app adds each one on its due date when it opens, with an
  Undo, never ahead of time. Pause, skip or edit them under Settings >
  Repeating transactions; Home shows what is due in the next 7 days. Editing a
  rule only changes what is added from then on, and deleting one keeps the
  transactions it already made.
- Backup (Settings): save everything (transactions, categories, settings) to
  one JSON file, restore it later or on a new phone, or export transactions as
  a CSV for a spreadsheet. The app only creates the file and opens the phone's
  share sheet; where it goes is your choice. Backup and CSV files are not
  encrypted. The temporary copy made for the share sheet is deleted about ten
  minutes later, and at the next start.
  Restoring checks the whole file first and replaces everything only if it is
  valid. Settings shows when the
  last backup file was made, and says so plainly after 30 days. Erase
  everything asks twice (and offers a backup first), then clears all data and
  starts the welcome tour again. Before an update that changes how data is
  stored, the app keeps one private copy of the database for 14 days. If the
  data cannot be opened, a recovery screen offers: try again, restore that
  copy, restore a backup file, or erase and start over. Backups larger than
  about half a megabyte are read and written in the background. "Save to a
  folder" opens the phone's own save dialog so you pick where the file goes.
  Home shows a quiet reminder card when the last backup is over 30 days old
  (or there are 10 or more transactions and none was ever made), with Back up
  now, Remind me later (a week) and Stop reminding me; a switch under Settings >
  Backup turns it back on. It is only a card: the app sends no notification and
  asks for no permission. About has a page of open-source licences.

Planned for later: multiple accounts.

## Your data and your phone's backup

Heisenbudget never sends anything anywhere: no server, no analytics, no
third-party service. The one way the data can leave the phone without you sending
a file is the phone's own backup, which the app does not control:

- **Android:** if Google's automatic backup is on, the app's database and
  preferences can be copied to your Google account and restored on a new phone.
- **iPhone:** if iCloud Backup (or a computer backup) is on, the app's data is
  included and restored onto a new device.

That copy is held by Google or Apple under their terms; the developer cannot see
it. Turn the phone's backup off in the phone's settings if you do not want it.
Erase everything and deleting the app do not delete older copies in those
backups. The privacy policy (published at the address in About) says the same.

## Run it

```sh
flutter pub get
dart run build_runner build      # generates the drift database code
flutter run                      # Android emulator/device, or an iPhone on a Mac
```

## Test it

```sh
flutter analyze
flutter test
```

## Build a release

The app id is `com.ajwadtahmid.heisenbudget` (Android application id and iOS
bundle identifier).

Android (works on Linux, macOS, Windows):

```sh
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

For Google Play the bundle is built by GitHub Actions: push a tag that matches
`pubspec.yaml` (for example `v1.0.0` for `version: 1.0.0+1`) and
`.github/workflows/build-release.yml` runs the tests, builds the obfuscated
bundle, and drafts a release with the `.aab`. It needs four repository secrets
(`KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`; the top of the
workflow says how to make them) and uploads the debug symbols as a private
artifact for 90 days. To build the same bundle on your own machine:

```sh
cp android/key.properties.example android/key.properties   # then fill it in (git-ignored)
tools/build_play_bundle.sh
# build/app/outputs/bundle/release/app-release.aab, and build/symbols/<version>
```

Without `android/key.properties` a release build is signed with the debug key,
which Play refuses. The script also fails if the merged release manifest asks for
the INTERNET permission. Keep `build/symbols/<version>` for every release you
publish: crash reports cannot be read without it.

iOS (needs a Mac with Xcode):

```sh
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace      # set your Team and a unique Bundle Identifier under Signing & Capabilities
flutter build ios --release      # or run on a plugged-in iPhone: flutter run --release
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/<version>   # for the App Store
```

`ITSAppUsesNonExemptEncryption` is set to false because the app has no
encryption of its own. If encryption is added (locked backups, an encrypted
database), decide the export-compliance answer again.

Then turn on airplane mode and check the app still works.

## Money and dates

- Amounts are stored as integer cents, never as floating point numbers.
- Dates are date-only text (`yyyy-MM-dd`), so there are no timezone or
  daylight-saving surprises.
- A balance counts transactions dated today or earlier; future-dated ones
  appear in period totals and History but join the balance when their day
  arrives.
- Amounts are typed without thousands separators: `1234.56` or `1234,56`.

## Project layout

```
lib/
  app_bootstrap.dart   opens the data before the app starts (or shows recovery)
  core/        constants, theme, design widgets, money parser, formatters
  data/        drift database (schema, start-up check, safety copy), repositories
               (transactions, categories, settings, repeating rules, favorites,
               budgets), the recurring catch-up service, backup (file format,
               restore, CSV, share sheet and file picker)
  domain/      pure Dart: DateRange and Period math, budget periods, repeat
               schedules, search matching, summaries, sort options
  providers/   Riverpod providers (no code generation)
  features/    shell, home, budgets, history, transaction_form, settings,
               recovery, shared widgets
test/          mirrors lib/
tools/         icon scripts and the Play Store bundle script
drift_schemas/ the frozen database schema (a migration test reads it)
```

Only `drift` generates code (`build_runner`); Riverpod is written by hand.
