import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/category_icons.dart';
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
  int get schemaVersion => 2;

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
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Drift's table DSL cannot express partial indexes, so these are by hand:
  /// one limit per category and month, and one overall limit per month (a
  /// plain unique index would let two null-category rows through).
  Future<void> _createBudgetIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX budget_limits_category_month '
      'ON budget_limits (category_id, start_month) '
      'WHERE category_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX budget_limits_overall_month '
      'ON budget_limits (start_month) WHERE category_id IS NULL',
    );
  }
}
