// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import '../../domain/budget.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<TransactionType>()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// True only for the two "Other" rows: they cannot be archived or renamed.
  BoolColumn get isProtected => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// A key from `categoryIcons` (e.g. `restaurant`), added in schema 2.
  // The literal is `defaultCategoryIconKey` (a test checks they match); the
  // frozen schema files cannot import it.
  TextColumn get icon => text().withDefault(const Constant('category'))();
}

@DataClassName('TransactionRow')
@TableIndex(name: 'transactions_date', columns: {#date})
@TableIndex(name: 'transactions_category', columns: {#categoryId})
// A repeating rule can create at most one transaction per day. NULLs (plain
// transactions) never clash with each other in a unique index.
@TableIndex(
  name: 'transactions_rule_date',
  columns: {#recurringRuleId, #date},
  unique: true,
)
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Always > 0. Money is stored as integer cents, never as a double.
  // The self-reference is drift's documented way to write a CHECK constraint
  // (see the ignore_for_file at the top).
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get type => textEnum<TransactionType>()();

  /// Local date, no time of day, as `yyyy-MM-dd`.
  TextColumn get date => text()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().nullable()();

  /// An optional short name shown before the category ("Corner Cafe · Food").
  TextColumn get title => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// The repeating rule that made this transaction. The rule going away leaves
  /// the transaction in place.
  IntColumn get recurringRuleId => integer().nullable().references(
    RecurringRules,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// A spending limit. From [start] (the first day of its first period) the
/// limit for a category (or, with no category, for all spending) is
/// [amountCents], repeating every [unit] or, when [repeats] is false, for that
/// one period only. A later row replaces it; a null amount means "no budget
/// from here". Rows are never rewritten for earlier periods: a change adds a
/// row that starts with the current period.
///
/// Unique per category and start day; the database also keeps one overall row
/// per start day (see the partial indexes in `AppDatabase`).
@DataClassName('BudgetLimitRow')
class BudgetLimits extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// An expense category, or null for the limit on all spending.
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();

  /// Days in one period (1 to 365); 0 when the period is counted in months.
  IntColumn get lengthDays =>
      integer().check(lengthDays.isBetweenValues(0, maxBudgetDays))();

  /// Budget months in one period (1 to 60); 0 when counted in days.
  IntColumn get lengthMonths => integer()
      .withDefault(const Constant(0))
      .check(lengthMonths.isBetweenValues(0, maxBudgetMonths))();

  /// False for a one-time budget (just its first period).
  BoolColumn get repeats => boolean().withDefault(const Constant(true))();

  /// `yyyy-MM-dd`: the first day of this row's first period.
  TextColumn get start => text()();

  /// In cents, or null for "no budget from here".
  IntColumn get amountCents =>
      integer().nullable().check(amountCents.isBiggerThanValue(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// A saved transaction to log again with one tap ("Coffee  $4.00").
@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// What the chip says, e.g. "Coffee".
  TextColumn get label => text()();
  TextColumn get type => textEnum<TransactionType>()();

  /// In cents. Null means "ask me each time" (a variable amount).
  IntColumn get amountCents => integer().nullable()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get title => text().nullable()();

  /// Position in the Quick add strip, lowest first.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// A transaction that repeats (rent, salary, a subscription). The app adds
/// its transactions itself when they fall due; see `RecurringService`.
@DataClassName('RecurringRuleRow')
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Always > 0, in cents, like a transaction.
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get type => textEnum<TransactionType>()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get title => text().nullable()();

  /// Repeats every [interval] [unit]s (1 to 365).
  TextColumn get unit => textEnum<RecurrenceUnit>()();
  IntColumn get interval => integer().withDefault(const Constant(1))();

  /// `yyyy-MM-dd`: the date occurrence 0 falls on and the day-of-month anchor.
  TextColumn get startDate => text()();

  /// `yyyy-MM-dd`, inclusive; null repeats forever.
  TextColumn get endDate => text().nullable()();

  /// False while paused.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// The next occurrence number to create. Everything before it has been
  /// created (or skipped), so deleting a created transaction never brings it
  /// back.
  IntColumn get nextIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}
