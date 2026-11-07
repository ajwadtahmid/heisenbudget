import 'package:drift/drift.dart';

import '../../domain/iso_date.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';
import '../repositories/category_repository.dart';
import 'csv_import.dart';

/// At most this many new categories are made from one file; the rest go to
/// "Other", so a messy file cannot bury the category list.
const maxImportedCategories = 50;

/// What an import would do with the readable rows.
class ImportAnalysis {
  const ImportAnalysis({
    required this.toImport,
    required this.duplicates,
    required this.newCategories,
    required this.toOther,
  });

  /// The rows that would be added.
  final List<ImportRow> toImport;

  /// Rows left out because the same transaction is already here.
  final int duplicates;

  /// Names of categories that would be created (empty when not creating).
  final List<String> newCategories;

  /// Rows that have no category, or one that is not made, and go to "Other".
  final int toOther;
}

/// What an import did.
class ImportResult {
  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.categoriesCreated,
  });

  final int imported;
  final int duplicates;
  final int categoriesCreated;
}

/// Adds the rows of a CSV file to the database in one transaction: all of
/// them, or, if anything fails, none.
class CsvImporter {
  CsvImporter(this._db);

  final AppDatabase _db;

  String _txKey(String iso, TransactionType type, int cents, String title) =>
      '$iso|${type.name}|$cents|${title.toLowerCase()}';

  String _catKey(TransactionType type, String name) =>
      '${type.name}|${name.toLowerCase()}';

  /// Works out, without changing anything, what [import] would do.
  Future<ImportAnalysis> analyze(
    List<ImportRow> rows, {
    required bool createCategories,
    required bool skipDuplicates,
  }) async {
    final plan = await _plan(
      rows,
      createCategories: createCategories,
      skipDuplicates: skipDuplicates,
    );
    return ImportAnalysis(
      toImport: plan.rows,
      duplicates: plan.duplicates,
      newCategories: plan.created.values.toList(),
      toOther: plan.toOther,
    );
  }

  Future<_Plan> _plan(
    List<ImportRow> rows, {
    required bool createCategories,
    required bool skipDuplicates,
  }) async {
    final good = rows.where((r) => r.ok).toList();
    final categories = await _db.select(_db.categories).get();
    final known = {for (final c in categories) _catKey(c.type, c.name)};

    // The same transaction already here is counted once per existing copy, so
    // two identical rows in the file are only both skipped when two exist.
    final existing = <String, int>{};
    if (skipDuplicates && good.isNotEmpty) {
      final dates = good.map((r) => toIsoDate(r.date!)).toList()..sort();
      final found = await (_db.select(
        _db.transactions,
      )..where((t) => t.date.isBetweenValues(dates.first, dates.last))).get();
      for (final t in found) {
        final k = _txKey(t.date, t.type, t.amountCents, t.title ?? '');
        existing[k] = (existing[k] ?? 0) + 1;
      }
    }

    // Category key -> the name to create, in the order first seen.
    final created = <String, String>{};
    var duplicates = 0;
    var toOther = 0;
    final kept = <ImportRow>[];
    for (final row in good) {
      if (skipDuplicates) {
        final k = _txKey(
          toIsoDate(row.date!),
          row.type!,
          row.cents!,
          row.title,
        );
        final left = existing[k] ?? 0;
        if (left > 0) {
          existing[k] = left - 1;
          duplicates++;
          continue;
        }
      }
      final name = row.category;
      if (name == null) {
        toOther++;
      } else {
        final key = _catKey(row.type!, name);
        if (!known.contains(key) && !created.containsKey(key)) {
          if (createCategories && created.length < maxImportedCategories) {
            created[key] = name;
          } else {
            toOther++;
          }
        }
      }
      kept.add(row);
    }
    return _Plan(kept, duplicates, created, toOther);
  }

  /// Adds the readable rows. [rows] are the rows from [readRows] as they are;
  /// unreadable ones are ignored here.
  Future<ImportResult> import(
    List<ImportRow> rows, {
    required bool createCategories,
    required bool skipDuplicates,
  }) {
    return _db.transaction(() async {
      final plan = await _plan(
        rows,
        createCategories: createCategories,
        skipDuplicates: skipDuplicates,
      );
      final categories = await _db.select(_db.categories).get();
      final ids = <String, int>{
        for (final c in categories) _catKey(c.type, c.name): c.id,
      };
      int otherFor(TransactionType type) =>
          categories.firstWhere((c) => c.type == type && c.isProtected).id;

      final repo = CategoryRepository(_db);
      var made = 0;
      for (final entry in plan.created.entries) {
        final type = entry.key.startsWith('income|')
            ? TransactionType.income
            : TransactionType.expense;
        try {
          ids[entry.key] = (await repo.add(entry.value, type)).id;
          made++;
        } on DuplicateCategoryException catch (e) {
          // An archived category with this name: use it as it is.
          final match = e.archivedMatch;
          if (match != null) ids[entry.key] = match.id;
        }
      }

      final now = DateTime.now();
      final companions = <TransactionsCompanion>[];
      for (final row in plan.rows) {
        final name = row.category;
        final id = name == null ? null : ids[_catKey(row.type!, name)];
        companions.add(
          TransactionsCompanion.insert(
            amountCents: row.cents!,
            type: row.type!,
            date: toIsoDate(row.date!),
            categoryId: id ?? otherFor(row.type!),
            note: Value(row.note.isEmpty ? null : row.note),
            title: Value(row.title.isEmpty ? null : row.title),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      for (var i = 0; i < companions.length; i += 500) {
        final end = i + 500 > companions.length ? companions.length : i + 500;
        final chunk = companions.sublist(i, end);
        await _db.batch((b) => b.insertAll(_db.transactions, chunk));
      }
      return ImportResult(
        imported: companions.length,
        duplicates: plan.duplicates,
        categoriesCreated: made,
      );
    });
  }
}

class _Plan {
  const _Plan(this.rows, this.duplicates, this.created, this.toOther);

  final List<ImportRow> rows;
  final int duplicates;
  final Map<String, String> created;
  final int toOther;
}
