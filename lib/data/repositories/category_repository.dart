import 'package:drift/drift.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';

/// Thrown when a category with the same name (ignoring case) already exists
/// for that type. [archivedMatch] is set when the clash is with an archived
/// category, so the UI can offer to restore it instead.
class DuplicateCategoryException implements Exception {
  const DuplicateCategoryException(this.name, {this.archivedMatch});

  final String name;
  final CategoryRow? archivedMatch;

  @override
  String toString() => 'A category named "$name" already exists';
}

/// Thrown when trying to archive or rename an "Other" category.
class ProtectedCategoryException implements Exception {
  const ProtectedCategoryException();

  @override
  String toString() => '"Other" cannot be archived or renamed';
}

/// Thrown for an empty (or whitespace-only) category name, or one longer
/// than [maxCategoryNameLength].
class InvalidCategoryNameException implements Exception {
  const InvalidCategoryNameException({this.tooLong = false});

  final bool tooLong;

  @override
  String toString() => tooLong
      ? 'Category name cannot be longer than $maxCategoryNameLength characters'
      : 'Category name cannot be empty';
}

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  $CategoriesTable get _t => _db.categories;

  /// Non-archived categories of one type, for pickers.
  Stream<List<CategoryRow>> watchActive(TransactionType type) {
    return (_db.select(_t)
          ..where((c) => c.type.equalsValue(type) & c.isArchived.equals(false))
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.id),
          ]))
        .watch();
  }

  /// Every category, including archived ones.
  Stream<List<CategoryRow>> watchAll() {
    return (_db.select(_t)..orderBy([
          (c) => OrderingTerm.asc(c.sortOrder),
          (c) => OrderingTerm.asc(c.id),
        ]))
        .watch();
  }

  Future<CategoryRow?> getById(int id) {
    return (_db.select(_t)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  /// Creates a custom category and returns it.
  Future<CategoryRow> add(
    String name,
    TransactionType type, {
    String icon = defaultCategoryIconKey,
  }) async {
    final clean = _cleanName(name);
    return _db.transaction(() async {
      await _rejectDuplicate(clean, type);
      final last =
          await (_db.selectOnly(_t)
                ..addColumns([_t.sortOrder.max()])
                ..where(_t.type.equalsValue(type)))
              .map((row) => row.read(_t.sortOrder.max()))
              .getSingle();
      final id = await _db
          .into(_t)
          .insert(
            CategoriesCompanion.insert(
              name: clean,
              type: type,
              icon: Value(icon),
              sortOrder: Value((last ?? -1) + 1),
            ),
          );
      return (await getById(id))!;
    });
  }

  Future<void> rename(int id, String name) async {
    final clean = _cleanName(name);
    await _db.transaction(() async {
      final category = await getById(id);
      if (category == null) return;
      if (category.isProtected) throw const ProtectedCategoryException();
      await _rejectDuplicate(clean, category.type, exceptId: id);
      await (_db.update(_t)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(name: Value(clean)),
      );
    });
  }

  /// Saves a new name and icon in one step (the edit dialog). The protected
  /// "Other" categories may change icon but keep their name.
  Future<void> update(
    int id, {
    required String name,
    required String icon,
  }) async {
    final clean = _cleanName(name);
    await _db.transaction(() async {
      final category = await getById(id);
      if (category == null) return;
      if (category.isProtected) {
        if (clean != category.name) throw const ProtectedCategoryException();
      } else {
        await _rejectDuplicate(clean, category.type, exceptId: id);
      }
      await (_db.update(_t)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(name: Value(clean), icon: Value(icon)),
      );
    });
  }

  /// "Deleting" a category: it disappears from pickers but old transactions
  /// keep showing it.
  Future<void> archive(int id) async {
    final category = await getById(id);
    if (category == null) return;
    if (category.isProtected) throw const ProtectedCategoryException();
    await _setArchived(id, true);
  }

  Future<void> restore(int id) => _setArchived(id, false);

  Future<void> _setArchived(int id, bool value) {
    return (_db.update(_t)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(isArchived: Value(value)),
    );
  }

  String _cleanName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) throw const InvalidCategoryNameException();
    if (clean.length > maxCategoryNameLength) {
      throw const InvalidCategoryNameException(tooLong: true);
    }
    return clean;
  }

  Future<void> _rejectDuplicate(
    String name,
    TransactionType type, {
    int? exceptId,
  }) async {
    final sameType = await (_db.select(
      _t,
    )..where((c) => c.type.equalsValue(type))).get();
    final lower = name.toLowerCase();
    for (final c in sameType) {
      if (c.id != exceptId && c.name.toLowerCase() == lower) {
        throw DuplicateCategoryException(
          name,
          archivedMatch: c.isArchived ? c : null,
        );
      }
    }
  }
}
