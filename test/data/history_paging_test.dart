import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/search.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/providers/history_providers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TransactionRepository txs;
  late CategoryRepository cats;
  late CategoryRow food;
  late CategoryRow rent;
  late CategoryRow salary;

  setUp(() async {
    db = AppDatabase.memory();
    txs = TransactionRepository(db);
    cats = CategoryRepository(db);
    final all = await cats.watchAll().first;
    food = all.firstWhere((c) => c.name == 'Food');
    rent = all.firstWhere((c) => c.name == 'Rent');
    salary = all.firstWhere((c) => c.name == 'Salary');
  });
  tearDown(() => db.close());

  Future<int> add(
    int cents,
    DateTime date, {
    CategoryRow? category,
    TransactionType type = TransactionType.expense,
    String? note,
    String? title,
  }) => txs.add(
    TransactionInput(
      amountCents: cents,
      type: type,
      date: date,
      categoryId:
          (category ?? (type == TransactionType.income ? salary : food)).id,
      note: note,
      title: title,
    ),
  );

  group('searching in the database gives the same answer as in Dart', () {
    Future<void> seed() async {
      await add(450, d(2026, 10, 1), note: 'Coffee with Sam');
      await add(499, d(2026, 10, 2), note: 'coffee beans');
      await add(500, d(2026, 10, 3), note: 'Bread');
      await add(1250, d(2026, 10, 4), category: rent, title: 'Flat');
      await add(450, d(2026, 10, 5), title: 'CAFÉ Noir');
      await add(7000, d(2026, 10, 6), note: 'কফি কেনা'); // Bangla
      await add(300, d(2026, 10, 7), note: 'Éclair');
      await add(450000, d(2026, 10, 8), type: TransactionType.income);
      await add(120000, d(2026, 10, 9), note: '1,234 deposit');
    }

    test('word by word, case, accents, Bangla, amounts, categories', () async {
      await seed();
      final everything = await txs.watchFiltered().first;
      for (final text in [
        'coffee',
        'COFFEE',
        'coffee 4',
        'coffee 4.50',
        'café',
        'éclair',
        'ÉCLAIR',
        'কফি',
        'rent',
        'flat 12',
        '12.50',
        '4',
        'food bread',
        '1,234',
        'nothing matches this',
        '  coffee   beans  ',
      ]) {
        final query = SearchQuery.parse(text);
        final expected = [
          for (final row in everything)
            if (query.matches(
              category: row.category.name,
              note: row.transaction.note,
              title: row.transaction.title,
              amountCents: row.transaction.amountCents,
            ))
              row.transaction.id,
        ];
        final actual = [
          for (final row in await txs.watchFiltered(search: text).first)
            row.transaction.id,
        ];
        expect(actual, expected, reason: '"$text"');
      }
    });

    test('is combined with the other filters and the sort', () async {
      await seed();
      final list = await txs
          .watchFiltered(
            search: 'coffee',
            range: DateRange(d(2026, 10, 2), d(2026, 10, 31)),
            sort: SortOption.highestAmount,
          )
          .first;
      expect(list.map((r) => r.transaction.amountCents), [499]);
    });

    test('a blank search is no search', () async {
      await seed();
      expect(
        (await txs.watchFiltered(search: '   ').first).length,
        (await txs.watchFiltered().first).length,
      );
    });
  });

  group('limit', () {
    test('returns only the first rows in the chosen order', () async {
      for (var i = 1; i <= 10; i++) {
        await add(i * 100, d(2026, 10, i));
      }
      final newest = await txs.watchFiltered(limit: 3).first;
      expect(newest.map((r) => r.transaction.amountCents), [1000, 900, 800]);
      final top = await txs
          .watchFiltered(sort: SortOption.lowestAmount, limit: 2)
          .first;
      expect(top.map((r) => r.transaction.amountCents), [100, 200]);
    });

    test('a page is read again when a transaction is added', () async {
      await add(100, d(2026, 10, 1));
      final seen = <int>[];
      final sub = txs.watchFiltered(limit: 2).listen((r) => seen.add(r.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await add(200, d(2026, 10, 2));
      await add(300, d(2026, 10, 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen.first, 1);
      expect(seen.last, 2, reason: 'never more than the limit');
    });
  });

  group('totals over the whole list', () {
    test('count and net follow the filter and the search', () async {
      await add(1000, d(2026, 10, 1), note: 'coffee');
      await add(2000, d(2026, 10, 2), note: 'coffee');
      await add(5000, d(2026, 10, 3), type: TransactionType.income);
      await add(700, d(2026, 10, 4), category: rent);

      var t = await txs.watchFilteredTotals().first;
      expect(
        (t.count, t.receivedCents, t.spentCents, t.netCents),
        (4, 5000, 3700, 1300),
      );
      t = await txs.watchFilteredTotals(search: 'coffee').first;
      expect((t.count, t.netCents), (2, -3000));
      t = await txs.watchFilteredTotals(type: TransactionType.income).first;
      expect((t.count, t.netCents), (1, 5000));
      t = await txs.watchFilteredTotals(search: 'no such thing').first;
      expect((t.count, t.netCents), (0, 0));
    });
  });

  group('historyPageOf', () {
    Future<List<TransactionWithCategory>> window(
      int limit, {
      SortOption sort = SortOption.newestFirst,
    }) => txs.watchFiltered(sort: sort, limit: limit + 1).first;

    test('everything fits: no more', () async {
      for (var i = 1; i <= 5; i++) {
        await add(100, d(2026, 10, i));
      }
      final page = historyPageOf(await window(10), 10, byDate: true);
      expect((page.rows.length, page.hasMore), (5, false));
    });

    test('a full page that is not the end says there is more', () async {
      for (var i = 1; i <= 8; i++) {
        await add(100, d(2026, 10, i));
      }
      final page = historyPageOf(await window(5), 5, byDate: true);
      expect((page.rows.length, page.hasMore), (5, true));
    });

    test('a day is never cut in half', () async {
      for (var i = 0; i < 6; i++) {
        await add(100 + i, d(2026, 10, 14)); // newest day: 6 rows
      }
      for (var i = 0; i < 6; i++) {
        await add(200 + i, d(2026, 10, 13)); // next day: 6 rows
      }
      final page = historyPageOf(await window(9), 9, byDate: true);
      // Nine would cut Oct 13 in half, so only Oct 14 is shown for now.
      expect(page.rows.length, 6);
      expect(
        page.rows.every((r) => r.transaction.date == '2026-10-14'),
        isTrue,
      );
      expect(page.hasMore, isTrue);
      // The next page completes the day.
      final next = historyPageOf(await window(18), 18, byDate: true);
      expect((next.rows.length, next.hasMore), (12, false));
    });

    test('one day bigger than a whole page is shown cut, not hidden', () async {
      for (var i = 0; i < 12; i++) {
        await add(100 + i, d(2026, 10, 14));
      }
      final page = historyPageOf(await window(5), 5, byDate: true);
      expect((page.rows.length, page.hasMore), (5, true));
    });

    test(
      'sorted by amount rows are cut at the limit, days do not matter',
      () async {
        for (var i = 0; i < 6; i++) {
          await add(100 + i, d(2026, 10, 14));
        }
        final page = historyPageOf(
          await window(4, sort: SortOption.highestAmount),
          4,
          byDate: false,
        );
        expect((page.rows.length, page.hasMore), (4, true));
      },
    );
  });

  group('spending for many ranges at once', () {
    test('matches counting each one alone', () async {
      await add(1000, d(2026, 10, 3));
      await add(2000, d(2026, 10, 20), category: rent);
      await add(500, d(2026, 11, 2));
      await add(9999, d(2026, 10, 5), type: TransactionType.income);
      final october = DateRange(d(2026, 10, 1), d(2026, 10, 31));
      final november = DateRange(d(2026, 11, 1), d(2026, 11, 30));
      final keys = <SpendKey>[
        (october, null),
        (october, food.id),
        (october, rent.id),
        (november, null),
        (DateRange(d(2025, 1, 1), d(2025, 1, 31)), null),
      ];
      final together = await txs.spentForKeys(keys);
      final alone = [
        for (final (range, cat) in keys)
          await txs.spentInRange(range, categoryId: cat),
      ];
      expect(together, alone);
      expect(together, [3000, 1000, 2000, 500, 0]);
    });

    test('more ranges than one query holds are split up', () async {
      await add(100, d(2026, 10, 3));
      final october = DateRange(d(2026, 10, 1), d(2026, 10, 31));
      final keys = <SpendKey>[
        for (var i = 0; i < 1200; i++) (october, i.isEven ? null : food.id),
      ];
      final spent = await txs.spentForKeys(keys);
      expect(spent, hasLength(1200));
      expect(spent.every((c) => c == 100), isTrue);
    });

    test('an empty list is an empty answer', () async {
      expect(await txs.spentForKeys(const []), isEmpty);
      expect(await txs.watchSpentForKeys(const []).first, isEmpty);
    });

    test('the watched version updates when a transaction is added', () async {
      final range = DateRange(d(2026, 10, 1), d(2026, 10, 31));
      final seen = <List<int>>[];
      final sub = txs
          .watchSpentForKeys([(range, null), (range, rent.id)])
          .listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await add(700, d(2026, 10, 9), category: rent);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen.first, [0, 0]);
      expect(seen.last, [700, 700]);
    });
  });

  test('the change signal goes up with every change and starts at 0', () async {
    final seen = <int>[];
    final sub = txs.watchChangeCount().listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = await add(100, d(2026, 10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await txs.delete(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.length, greaterThanOrEqualTo(3));
    expect(seen, orderedEquals([...seen]..sort()));
  });
}
