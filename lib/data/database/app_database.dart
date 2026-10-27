import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/category_icons.dart';
import '../../domain/budget.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import 'seed.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Categories, Transactions, RecurringRules, Favorites, BudgetLimits],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// The real on-device database.
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'heisenbudget'));

  /// A throwaway in-memory database for tests.
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Case-insensitive uniqueness per type. Drift's table DSL cannot
      // express COLLATE NOCASE, so it is added by hand.
      await customStatement(
        'CREATE UNIQUE INDEX categories_type_name '
        'ON categories (type, name COLLATE NOCASE)',
      );
      await _createBudgetIndexes();
      await seedDefaultCategories(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Schema 2: categories got an icon.
        await m.addColumn(categories, categories.icon);
        await applyDefaultIcons(this);
        // Repeating transactions and favorites joined schema 2 before the
        // first release, so a database upgraded from schema 1 gets them in
        // the same step.
        await m.createTable(recurringRules);
        await m.addColumn(transactions, transactions.recurringRuleId);
        await m.addColumn(transactions, transactions.title);
        await m.createIndex(transactionsRuleDate);
        await m.createTable(favorites);
        await m.createTable(budgetLimits);
        await _createBudgetIndexes();
      } else if (from < 3) {
        await _upgradeBudgetLimits(m);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Schema 3: a budget's length may be counted in months. Installs made
  /// while budgets were being built have one of two older table shapes, and
  /// both are brought up to date without losing a saved budget.
  Future<void> _upgradeBudgetLimits(Migrator m) async {
    final info = await customSelect('PRAGMA table_info(budget_limits)').get();
    final columns = {for (final row in info) row.read<String>('name')};
    if (columns.contains('length_months')) return;
    if (columns.contains('unit')) {
      // The period was a text name (week, fortnight, month).
      await customStatement(
        'DROP INDEX IF EXISTS budget_limits_category_start',
      );
      await customStatement('DROP INDEX IF EXISTS budget_limits_overall_start');
      await customStatement(
        'ALTER TABLE budget_limits RENAME TO budget_limits_old',
      );
      await m.createTable(budgetLimits);
      await customStatement(
        'INSERT INTO budget_limits (id, category_id, length_days, '
        'length_months, repeats, start, amount_cents, created_at) '
        'SELECT id, category_id, '
        "CASE unit WHEN 'week' THEN 7 WHEN 'fortnight' THEN 14 ELSE 0 END, "
        "CASE unit WHEN 'week' THEN 0 WHEN 'fortnight' THEN 0 ELSE 1 END, "
        'repeats, start, amount_cents, created_at FROM budget_limits_old',
      );
      await customStatement('DROP TABLE budget_limits_old');
      await _createBudgetIndexes();
    } else if (columns.contains('length_days')) {
      // Zero days used to mean a month.
      await m.addColumn(budgetLimits, budgetLimits.lengthMonths);
      await customStatement(
        'UPDATE budget_limits SET length_months = 1, length_days = 0 '
        'WHERE length_days = 0',
      );
    }
  }

  /// Drift's table DSL cannot express partial indexes, so these are by hand:
  /// one limit per category and first day, and one overall limit per first day (a
  /// plain unique index would let two null-category rows through).
  Future<void> _createBudgetIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX budget_limits_category_start '
      'ON budget_limits (category_id, start) '
      'WHERE category_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX budget_limits_overall_start '
      'ON budget_limits (start) WHERE category_id IS NULL',
    );
  }
}
