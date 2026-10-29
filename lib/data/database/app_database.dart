import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/budget.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import 'seed.dart';
import 'sql_functions.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The first public schema. Every change after it needs a version bump, a
/// migration step in [AppDatabase.migration], a new `drift_schemas/` dump
/// (`dart run drift_dev schema dump lib/data/database/app_database.dart
/// drift_schemas/`) and a test from the older version.
const currentSchemaVersion = 4;

@DriftDatabase(
  tables: [
    Categories,
    Transactions,
    RecurringRules,
    Favorites,
    BudgetLimits,
    SavingsGoals,
    GoalEntries,
  ],
  include: {'indexes.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// The real on-device database, stored in [file].
  factory AppDatabase.open(File file) => AppDatabase(
    driftDatabase(
      name: 'heisenbudget',
      native: DriftNativeOptions(
        databasePath: () async => file.path,
        setup: registerSqlFunctions,
      ),
    ),
  );

  /// A throwaway in-memory database for tests.
  factory AppDatabase.memory() =>
      AppDatabase(NativeDatabase.memory(setup: registerSqlFunctions));

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Tables and the indexes in `indexes.drift`.
      await m.createAll();
      await seedDefaultCategories(this);
    },
    onUpgrade: (m, from, to) async {
      // Schema 3 is where public installs begin. An unknown version (an older
      // development build, or a newer app's file) stops here, and the start-up
      // check shows the recovery screen.
      if (from < 3 || from > to) {
        throw UnsupportedError(
          'This database is at schema $from; this app uses schema $to.',
        );
      }
      // 3 to 4: savings goals and their entries.
      if (from < 4) {
        await m.createTable(savingsGoals);
        await m.createTable(goalEntries);
        await m.createIndex(goalEntriesGoal);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
