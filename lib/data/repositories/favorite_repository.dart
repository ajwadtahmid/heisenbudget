import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';

/// Thrown when adding a favorite beyond [maxFavorites].
class FavoriteLimitException implements Exception {
  const FavoriteLimitException();

  @override
  String toString() => 'You can have up to $maxFavorites favorites';
}

/// The values a favorite is made from. A null [amountCents] means the amount
/// is asked for each time.
class FavoriteInput {
  const FavoriteInput({
    required this.label,
    required this.type,
    required this.categoryId,
    this.amountCents,
    this.note,
    this.title,
  });

  final String label;
  final TransactionType type;
  final int categoryId;
  final int? amountCents;
  final String? note;
  final String? title;

  void validate() {
    final name = label.trim();
    if (name.isEmpty || name.length > maxFavoriteLabelLength) {
      throw ArgumentError.value(
        label,
        'label',
        'must be 1 to '
            '$maxFavoriteLabelLength characters',
      );
    }
    final cents = amountCents;
    if (cents != null && (cents < 1 || cents > maxAmountCents)) {
      throw RangeError.range(cents, 1, maxAmountCents, 'amountCents');
    }
    if ((title?.length ?? 0) > maxTitleLength) {
      throw ArgumentError.value(title, 'title', 'longer than $maxTitleLength');
    }
    if ((note?.length ?? 0) > maxNoteLength) {
      throw ArgumentError.value(note, 'note', 'longer than $maxNoteLength');
    }
  }
}

class FavoriteRepository {
  FavoriteRepository(this._db);

  final AppDatabase _db;

  $FavoritesTable get _f => _db.favorites;

  /// In strip order.
  Stream<List<FavoriteRow>> watchAll() {
    return (_db.select(_f)..orderBy([
          (f) => OrderingTerm.asc(f.sortOrder),
          (f) => OrderingTerm.asc(f.id),
        ]))
        .watch();
  }

  Future<FavoriteRow?> getById(int id) {
    return (_db.select(_f)..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  /// Adds a favorite at the end of the strip. Throws
  /// [FavoriteLimitException] when there are already [maxFavorites].
  Future<int> add(FavoriteInput input) {
    input.validate();
    return _db.transaction(() async {
      await _checkCategory(input);
      final count = await (_db.selectOnly(_f)..addColumns([_f.id.count()]))
          .map((r) => r.read(_f.id.count()))
          .getSingle();
      if ((count ?? 0) >= maxFavorites) throw const FavoriteLimitException();
      final last = await (_db.selectOnly(_f)..addColumns([_f.sortOrder.max()]))
          .map((r) => r.read(_f.sortOrder.max()))
          .getSingle();
      return _db
          .into(_f)
          .insert(
            FavoritesCompanion.insert(
              label: input.label.trim(),
              type: input.type,
              amountCents: Value(input.amountCents),
              categoryId: input.categoryId,
              note: Value(_cleanNote(input.note)),
              title: Value(_cleanNote(input.title)),
              sortOrder: Value((last ?? -1) + 1),
              createdAt: DateTime.now(),
            ),
          );
    });
  }

  /// Saves edits. The type of a favorite cannot change.
  Future<void> update(int id, FavoriteInput input) {
    input.validate();
    return _db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return;
      await _checkCategory(
        FavoriteInput(
          label: input.label,
          type: existing.type,
          categoryId: input.categoryId,
        ),
      );
      await (_db.update(_f)..where((f) => f.id.equals(id))).write(
        FavoritesCompanion(
          label: Value(input.label.trim()),
          amountCents: Value(input.amountCents),
          categoryId: Value(input.categoryId),
          note: Value(_cleanNote(input.note)),
          title: Value(_cleanNote(input.title)),
        ),
      );
    });
  }

  Future<void> delete(int id) async {
    await (_db.delete(_f)..where((f) => f.id.equals(id))).go();
  }

  /// Puts the favorites in the order of [ids] (first = leftmost). Ids that are
  /// not listed keep their place after the listed ones.
  Future<void> reorder(List<int> ids) {
    return _db.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (_db.update(_f)..where((f) => f.id.equals(ids[i]))).write(
          FavoritesCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  Future<void> _checkCategory(FavoriteInput input) async {
    final category = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(input.categoryId))).getSingleOrNull();
    if (category == null || category.type != input.type) {
      throw ArgumentError.value(
        input.categoryId,
        'categoryId',
        'must be a ${input.type.name} category',
      );
    }
  }

  String? _cleanNote(String? note) {
    final clean = note?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
