# Heisenbudget

A simple personal expense and income tracker for Android and iOS, with a light
chemistry-lab look. It works **100% offline**: no accounts, no internet, no
cloud, no analytics. Everything is stored on the device.

> Not affiliated with or endorsed by any TV show or its owners. The name is a
> pun on a physicist's name; the icon, colors and wording are original.

## What it does

- Shows your balance and Received / Spent / Net for a period you choose from one
  compact menu: this week, this month, Week 1 to N of a month, or a custom
  date range.
- Adds, edits and deletes income and expenses from a bottom sheet (amount,
  date, category, note).
- History tab: grouped by day, filter by type, category and date (All time,
  this week, this month, last month, custom), sort, swipe to delete with Undo.
- Every category has an icon, picked from about 240 built-in Material icons in
  labelled sections with a search box. Change any of them, and pick one when you
  make your own. Archive and restore categories.
- A calm "instrument" look: ruled readouts in tabular mono numbers, a tick
  ruler showing how far through the period you are, and a spectrum chart of
  spending by category (tap a peak for the exact share).
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
  Export to CSV and Erase everything. About has the version, how your data is
  kept, the licences and the not-affiliated note.

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
  for it.
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
  share sheet; where it goes is your choice. Restoring checks the whole file
  first and replaces everything only if it is valid. Settings shows when the
  last backup file was made, and says so plainly after 30 days. Erase
  everything asks twice (and offers a backup first), then clears all data and
  starts the welcome tour again.

Planned for later: budgets, multiple accounts.

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

Android (works on Linux, macOS, Windows):

```sh
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

iOS (needs a Mac with Xcode):

```sh
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace      # set your Team and a unique Bundle Identifier under Signing & Capabilities
flutter build ios --release      # or run on a plugged-in iPhone: flutter run --release
```

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
  core/        constants, theme, money parser, formatters
  data/        drift database, repositories (transactions, categories, settings,
               repeating rules, favorites), the recurring catch-up service,
               backup (file format, restore, CSV, share sheet and file picker)
  domain/      pure Dart: DateRange and Period math, repeat schedules,
               search matching, summaries, sort options
  providers/   Riverpod providers (no code generation)
  features/    shell, home, history, transaction_form, settings, shared widgets
test/          mirrors lib/
extra/AGENTS_BUILD_PLAN.md   the build plan the app was made from
```

Only `drift` generates code (`build_runner`); Riverpod is written by hand.
