import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/category_spend.dart';
import '../../domain/date_range.dart';
import '../../domain/iso_date.dart';
import '../../domain/sort_option.dart';
import '../../domain/summary.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';

/// A transaction together with its category (archived or not).
class TransactionWithCategory {
  const TransactionWithCategory(this.transaction, this.category);

  final TransactionRow transaction;
  final CategoryRow category;
}

/// The values the user enters for a transaction.
class TransactionInput {
  const TransactionInput({
    required this.amountCents,
    required this.type,
    required this.date,
    required this.categoryId,
    this.note,
  });

  final int amountCents;
  final TransactionType type;
  final DateTime date;
  final int categoryId;
  final String? note;

  /// Copies the saved values of an existing row (used by Undo on delete).
  factory TransactionInput.fromRow(TransactionRow row) => TransactionInput(
    amountCents: row.amountCents,
    type: row.type,
    date: fromIsoDate(row.date),
    categoryId: row.categoryId,
    note: row.note,
  );

  void validate() {
    if (amountCents < 1 || amountCents > maxAmountCents) {
      throw RangeError.range(amountCents, 1, maxAmountCents, 'amountCents');
    }
    if ((note?.length ?? 0) > maxNoteLength) {
      throw ArgumentError.value(note, 'note', 'longer than $maxNoteLength');
    }
  }
}

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  $TransactionsTable get _t => _db.transactions;
  $CategoriesTable get _c => _db.categories;

  Future<int> add(TransactionInput input) async {
    input.validate();
    final now = DateTime.now();
    return _db
        .into(_t)
        .insert(
          TransactionsCompanion.insert(
            amountCents: input.amountCents,
            type: input.type,
            date: toIsoDate(input.date),
            categoryId: input.categoryId,
            note: Value(_cleanNote(input.note)),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> update(int id, TransactionInput input) async {
    input.validate();
    await (_db.update(_t)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        amountCents: Value(input.amountCents),
        type: Value(input.type),
        date: Value(toIsoDate(input.date)),
        categoryId: Value(input.categoryId),
        note: Value(_cleanNote(input.note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) async {
    await (_db.delete(_t)..where((t) => t.id.equals(id))).go();
  }

  Future<TransactionWithCategory?> getById(int id) async {
    final rows = await (_joined()..where(_t.id.equals(id))).get();
    return rows.isEmpty ? null : _toModel(rows.first);
  }

  /// Transactions dated inside [range] (both ends inclusive), newest first.
  Stream<List<TransactionWithCategory>> watchByRange(
    DateRange range, {
    int? limit,
  }) {
    final query = _joined()
      ..where(_inRange(range))
      ..orderBy(_ordering(SortOption.newestFirst));
    if (limit != null) query.limit(limit);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// History list. Every filter is optional; an empty [categoryIds] means
  /// "all categories" and a null [range] means "all time".
  Stream<List<TransactionWithCategory>> watchFiltered({
    TransactionType? type,
    Set<int> categoryIds = const {},
    DateRange? range,
    SortOption sort = SortOption.newestFirst,
  }) {
    final query = _joined();
    if (type != null) query.where(_t.type.equalsValue(type));
    if (categoryIds.isNotEmpty) query.where(_t.categoryId.isIn(categoryIds));
    if (range != null) query.where(_inRange(range));
    query.orderBy(_ordering(sort));
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Ids of categories that at least one transaction uses. History's filter
  /// offers archived categories only if they are in this set.
  Stream<Set<int>> watchUsedCategoryIds() {
    final query = _db.selectOnly(_t, distinct: true)
      ..addColumns([_t.categoryId]);
    return query.watch().map(
      (rows) => rows.map((r) => r.read(_t.categoryId)!).toSet(),
    );
  }

  /// Expense totals per category inside [range], biggest first (summed in SQL).
  /// Feeds the spending chart.
  Stream<List<CategorySpend>> watchSpendByCategory(DateRange range) {
    final total = _t.amountCents.sum();
    final query =
        _db.select(_t).join([innerJoin(_c, _c.id.equalsExp(_t.categoryId))])
          ..addColumns([total])
          ..where(
            _t.type.equalsValue(TransactionType.expense) & _inRange(range),
          )
          ..groupBy([_c.id])
          ..orderBy([OrderingTerm.desc(total), OrderingTerm.asc(_c.name)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          CategorySpend(
            categoryId: row.readTable(_c).id,
            name: row.readTable(_c).name,
            icon: row.readTable(_c).icon,
            cents: row.read(total) ?? 0,
          ),
      ],
    );
  }

  /// Whether any transaction exists (used to skip the first-run tour for
  /// people who already have data).
  Future<bool> hasAny() async {
    final row = await (_db.selectOnly(
      _t,
    )..addColumns([_t.id.count()])).getSingle();
    return (row.read(_t.id.count()) ?? 0) > 0;
  }

  /// Received/Spent totals for a range, summed in SQL.
  Stream<Summary> watchSummary(DateRange range) => _watchSums(_inRange(range));

  /// Totals for everything dated on or before [date]; feeds the balance.
  Stream<Summary> watchTotalsUpTo(DateTime date) {
    return _watchSums(_t.date.isSmallerOrEqualValue(toIsoDate(date)));
  }

  Stream<Summary> _watchSums(Expression<bool> where) {
    final received = _t.amountCents.sum(
      filter: _t.type.equalsValue(TransactionType.income),
    );
    final spent = _t.amountCents.sum(
      filter: _t.type.equalsValue(TransactionType.expense),
    );
    final query = _db.selectOnly(_t)
      ..addColumns([received, spent])
      ..where(where);
    return query.watchSingle().map(
      (row) => Summary(
        receivedCents: row.read(received) ?? 0,
        spentCents: row.read(spent) ?? 0,
      ),
    );
  }

  Expression<bool> _inRange(DateRange range) =>
      _t.date.isBetweenValues(toIsoDate(range.start), toIsoDate(range.end));

  JoinedSelectStatement<HasResultSet, dynamic> _joined() {
    return _db.select(_t).join([innerJoin(_c, _c.id.equalsExp(_t.categoryId))]);
  }

  TransactionWithCategory _toModel(TypedResult row) =>
      TransactionWithCategory(row.readTable(_t), row.readTable(_c));

  List<OrderingTerm> _ordering(SortOption sort) {
    // id breaks ties so the order is always stable.
    return switch (sort) {
      SortOption.newestFirst => [
        OrderingTerm.desc(_t.date),
        OrderingTerm.desc(_t.id),
      ],
      SortOption.oldestFirst => [
        OrderingTerm.asc(_t.date),
        OrderingTerm.asc(_t.id),
      ],
      SortOption.highestAmount => [
        OrderingTerm.desc(_t.amountCents),
        OrderingTerm.desc(_t.date),
        OrderingTerm.desc(_t.id),
      ],
      SortOption.lowestAmount => [
        OrderingTerm.asc(_t.amountCents),
        OrderingTerm.desc(_t.date),
        OrderingTerm.desc(_t.id),
      ],
    };
  }

  /// Blank notes are stored as null.
  String? _cleanNote(String? note) {
    final clean = note?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
