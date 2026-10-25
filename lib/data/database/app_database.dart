import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/category_icons.dart';
import '../../domain/transaction_type.dart';
import 'seed.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Transactions])
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
      await seedDefaultCategories(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Schema 2: categories got an icon.
        await m.addColumn(categories, categories.icon);
        await applyDefaultIcons(this);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
