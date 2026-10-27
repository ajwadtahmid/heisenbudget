import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/category_spend.dart';
import '../../domain/date_range.dart';
import '../../domain/iso_date.dart';
import '../../domain/sort_option.dart';
import '../../domain/summary.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';
import '../database/sql_functions.dart';

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
    this.title,
  });

  final int amountCents;
  final TransactionType type;
  final DateTime date;
  final int categoryId;
  final String? note;

  /// An optional short name shown before the category.
  final String? title;

  /// Copies the saved values of an existing row (used by Undo on delete).
  factory TransactionInput.fromRow(TransactionRow row) => TransactionInput(
    amountCents: row.amountCents,
    type: row.type,
    date: fromIsoDate(row.date),
    categoryId: row.categoryId,
    note: row.note,
    title: row.title,
  );

  void validate() {
    if (amountCents < 1 || amountCents > maxAmountCents) {
      throw RangeError.range(amountCents, 1, maxAmountCents, 'amountCents');
    }
    if ((title?.length ?? 0) > maxTitleLength) {
      throw ArgumentError.value(title, 'title', 'longer than $maxTitleLength');
    }
    if ((note?.length ?? 0) > maxNoteLength) {
      throw ArgumentError.value(note, 'note', 'longer than $maxNoteLength');
    }
  }
}

/// What a filtered History list adds up to: how many transactions, and the
/// totals, counted over the whole list (not just the part loaded).
class FilteredTotals {
  const FilteredTotals({
    required this.count,
    required this.receivedCents,
    required this.spentCents,
  });

  final int count;
  final int receivedCents;
  final int spentCents;

  int get netCents => receivedCents - spentCents;
}

/// One thing to total spending for: a date range and one category (null = all).
typedef SpendKey = (DateRange range, int? categoryId);

/// SQLite allows 2000 columns in one query; stay well under it.
const _spendKeysPerQuery = 500;

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
            title: Value(_cleanNote(input.title)),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Saves edits. [unlinkRule] detaches the transaction from its repeating
  /// rule (used when its date is changed, so it no longer fills that slot).
  Future<void> update(
    int id,
    TransactionInput input, {
    bool unlinkRule = false,
  }) async {
    input.validate();
    await (_db.update(_t)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        amountCents: Value(input.amountCents),
        type: Value(input.type),
        date: Value(toIsoDate(input.date)),
        categoryId: Value(input.categoryId),
        note: Value(_cleanNote(input.note)),
        title: Value(_cleanNote(input.title)),
        updatedAt: Value(DateTime.now()),
        recurringRuleId: unlinkRule ? const Value(null) : const Value.absent(),
      ),
    );
  }

  Future<void> delete(int id) async {
    await (_db.delete(_t)..where((t) => t.id.equals(id))).go();
  }

  /// Deletes several transactions at once (Undo of a recurring catch-up).
  Future<void> deleteMany(Iterable<int> ids) async {
    await (_db.delete(_t)..where((t) => t.id.isIn(ids))).go();
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
  /// "all categories" and a null [range] means "all time". [search] keeps
  /// rows that match every word (see `SearchQuery`), and [limit] returns only
  /// the first rows in the chosen order, so a long history is read a page at
  /// a time.
  Stream<List<TransactionWithCategory>> watchFiltered({
    TransactionType? type,
    Set<int> categoryIds = const {},
    DateRange? range,
    SortOption sort = SortOption.newestFirst,
    String search = '',
    int? limit,
  }) {
    final query = _joined();
    for (final condition in _filter(type, categoryIds, range, search)) {
      query.where(condition);
    }
    query.orderBy(_ordering(sort));
    if (limit != null) query.limit(limit);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// How many transactions the same filter matches and what they add up to,
  /// over the whole list.
  Stream<FilteredTotals> watchFilteredTotals({
    TransactionType? type,
    Set<int> categoryIds = const {},
    DateRange? range,
    String search = '',
  }) {
    final count = _t.id.count();
    final received = _t.amountCents.sum(
      filter: _t.type.equalsValue(TransactionType.income),
    );
    final spent = _t.amountCents.sum(
      filter: _t.type.equalsValue(TransactionType.expense),
    );
    final query = _db.selectOnly(_t).join([
      innerJoin(_c, _c.id.equalsExp(_t.categoryId)),
    ])..addColumns([count, received, spent]);
    for (final condition in _filter(type, categoryIds, range, search)) {
      query.where(condition);
    }
    return query.watchSingle().map(
      (row) => FilteredTotals(
        count: row.read(count) ?? 0,
        receivedCents: row.read(received) ?? 0,
        spentCents: row.read(spent) ?? 0,
      ),
    );
  }

  List<Expression<bool>> _filter(
    TransactionType? type,
    Set<int> categoryIds,
    DateRange? range,
    String search,
  ) => [
    if (type != null) _t.type.equalsValue(type),
    if (categoryIds.isNotEmpty) _t.categoryId.isIn(categoryIds),
    if (range != null) _inRange(range),
    if (search.trim().isNotEmpty)
      FunctionCallExpression<int>(searchFunctionName, [
        _c.name,
        _t.note,
        _t.title,
        _t.amountCents,
        Variable<String>(search),
      ]).equals(1),
  ];

  /// Every transaction, oldest first (for the CSV export).
  Future<List<TransactionWithCategory>> getAll() async {
    final rows = await (_joined()..orderBy(_ordering(SortOption.oldestFirst)))
        .get();
    return rows.map(_toModel).toList();
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

  /// Expenses dated inside [range] (both ends inclusive), in cents, for one
  /// category or, with none given, for all of them.
  Future<int> spentInRange(DateRange range, {int? categoryId}) async {
    final total = _t.amountCents.sum();
    final query = _db.selectOnly(_t)
      ..addColumns([total])
      ..where(
        _t.type.equalsValue(TransactionType.expense) &
            _inRange(range) &
            (categoryId == null
                ? const Constant(true)
                : _t.categoryId.equals(categoryId)),
      );
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// [spentInRange], kept up to date as transactions change.
  Stream<int> watchSpentInRange(DateRange range, {int? categoryId}) {
    final total = _t.amountCents.sum();
    final query = _db.selectOnly(_t)
      ..addColumns([total])
      ..where(
        _t.type.equalsValue(TransactionType.expense) &
            _inRange(range) &
            (categoryId == null
                ? const Constant(true)
                : _t.categoryId.equals(categoryId)),
      );
    return query.watchSingle().map((row) => row.read(total) ?? 0);
  }

  /// Expenses for each of [keys] (a range and a category, or null for all),
  /// in the same order. One query for many figures, so a whole page of past
  /// budgets is counted at once.
  Future<List<int>> spentForKeys(List<SpendKey> keys) async {
    final out = <int>[];
    for (var i = 0; i < keys.length; i += _spendKeysPerQuery) {
      final chunk = keys.sublist(
        i,
        i + _spendKeysPerQuery > keys.length
            ? keys.length
            : i + _spendKeysPerQuery,
      );
      final columns = _spendColumns(chunk);
      final row = await _spendQuery(chunk, columns).getSingle();
      out.addAll([for (final c in columns) row.read(c) ?? 0]);
    }
    return out;
  }

  /// [spentForKeys], kept up to date as transactions change: one stream for
  /// all the budgets on screen, not one per budget. Up to
  /// [_spendKeysPerQuery] keys.
  Stream<List<int>> watchSpentForKeys(List<SpendKey> keys) {
    if (keys.isEmpty) return Stream.value(const []);
    if (keys.length > _spendKeysPerQuery) {
      throw ArgumentError.value(
        keys.length,
        'keys',
        'too many to watch at once',
      );
    }
    final columns = _spendColumns(keys);
    return _spendQuery(
      keys,
      columns,
    ).watchSingle().map((row) => [for (final c in columns) row.read(c) ?? 0]);
  }

  List<Expression<int>> _spendColumns(List<SpendKey> keys) => [
    for (final (range, categoryId) in keys)
      _t.amountCents.sum(
        filter:
            _t.type.equalsValue(TransactionType.expense) &
            _inRange(range) &
            (categoryId == null
                ? const Constant(true)
                : _t.categoryId.equals(categoryId)),
      ),
  ];

  JoinedSelectStatement<$TransactionsTable, TransactionRow> _spendQuery(
    List<SpendKey> keys,
    List<Expression<int>> columns,
  ) {
    var from = keys.first.$1.start;
    var to = keys.first.$1.end;
    for (final (range, _) in keys) {
      if (range.start.isBefore(from)) from = range.start;
      if (range.end.isAfter(to)) to = range.end;
    }
    // Only rows that can count, so the date index narrows the scan.
    return _db.selectOnly(_t)
      ..addColumns(columns)
      ..where(
        _t.type.equalsValue(TransactionType.expense) &
            _inRange(DateRange(from, to)),
      );
  }

  /// A number that goes up each time any transaction is added, changed or
  /// removed (and starts at 0): a cheap "something changed" signal.
  Stream<int> watchChangeCount() {
    // A controller, not `async*`: cancelling must stop listening at once.
    late final StreamController<int> controller;
    StreamSubscription<void>? updates;
    var n = 0;
    controller = StreamController<int>(
      onListen: () {
        controller.add(n);
        updates = _db
            .tableUpdates(TableUpdateQuery.onTable(_t))
            .listen((_) => controller.add(++n));
      },
      onCancel: () => updates?.cancel(),
    );
    return controller.stream;
  }

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
