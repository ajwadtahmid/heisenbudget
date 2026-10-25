// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import '../../core/category_icons.dart';
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
  TextColumn get icon =>
      text().withDefault(const Constant(defaultCategoryIconKey))();
}

@DataClassName('TransactionRow')
@TableIndex(name: 'transactions_date', columns: {#date})
@TableIndex(name: 'transactions_category', columns: {#categoryId})
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
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
