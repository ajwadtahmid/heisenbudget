import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
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
    CategoryRow find(String name, TransactionType type) =>
        all.firstWhere((c) => c.name == name && c.type == type);
    food = find('Food', TransactionType.expense);
    rent = find('Rent', TransactionType.expense);
    salary = find('Salary', TransactionType.income);
  });

  tearDown(() => db.close());

  Future<int> addExpense(int cents, DateTime date, {CategoryRow? category}) {
    return txs.add(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.expense,
        date: date,
        categoryId: (category ?? food).id,
      ),
    );
  }

  Future<int> addIncome(int cents, DateTime date) {
    return txs.add(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.income,
        date: date,
        categoryId: salary.id,
      ),
    );
  }

  group('TransactionRepository', () {
    test('add, getById, update, delete', () async {
      final id = await txs.add(
        TransactionInput(
          amountCents: 1250,
          type: TransactionType.expense,
          date: d(2026, 10, 5),
          categoryId: food.id,
          note: '  lunch  ',
        ),
      );

      var found = (await txs.getById(id))!;
      expect(found.transaction.amountCents, 1250);
      expect(found.transaction.date, '2026-10-05');
      expect(found.transaction.note, 'lunch');
      expect(found.category.name, 'Food');

      await txs.update(
        id,
        TransactionInput(
          amountCents: 3000,
          type: TransactionType.income,
          date: d(2026, 10, 6),
          categoryId: salary.id,
          note: '   ',
        ),
      );
      found = (await txs.getById(id))!;
      expect(found.transaction.amountCents, 3000);
      expect(found.transaction.type, TransactionType.income);
      expect(found.transaction.date, '2026-10-06');
      expect(found.transaction.note, isNull, reason: 'blank note -> null');
      expect(found.category.name, 'Salary');

      await txs.delete(id);
      expect(await txs.getById(id), isNull);
    });

    test('rejects out-of-range amounts and long notes', () async {
      expect(() => addExpense(0, d(2026, 10, 1)), throwsRangeError);
      expect(() => addExpense(-5, d(2026, 10, 1)), throwsRangeError);
      expect(() => addExpense(100000000000, d(2026, 10, 1)), throwsRangeError);
      await addExpense(99999999999, d(2026, 10, 1)); // max is allowed
      expect(
        () => txs.add(
          TransactionInput(
            amountCents: 100,
            type: TransactionType.expense,
            date: d(2026, 10, 1),
            categoryId: food.id,
            note: 'x' * 201,
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'range queries include transactions on the start and end dates',
      () async {
        await addExpense(100, d(2026, 9, 30)); // just before
        await addExpense(200, d(2026, 10, 1)); // start
        await addExpense(300, d(2026, 10, 15));
        await addExpense(400, d(2026, 10, 31)); // end
        await addExpense(500, d(2026, 11, 1)); // just after

        final october = monthOf(2026, 10);
        final list = await txs.watchByRange(october).first;
        expect(list.map((t) => t.transaction.amountCents), [400, 300, 200]);

        final limited = await txs.watchByRange(october, limit: 2).first;
        expect(limited.map((t) => t.transaction.amountCents), [400, 300]);
      },
    );

    test('watchSummary sums in SQL for the range only', () async {
      await addIncome(100000, d(2026, 10, 1));
      await addExpense(2500, d(2026, 10, 2));
      await addExpense(1000, d(2026, 10, 31));
      await addExpense(9999, d(2026, 11, 1)); // outside

      final summary = await txs.watchSummary(monthOf(2026, 10)).first;
      expect(summary.receivedCents, 100000);
      expect(summary.spentCents, 3500);
      expect(summary.netCents, 96500);
    });

    test('summary of an empty range is zero', () async {
      final summary = await txs.watchSummary(monthOf(2026, 10)).first;
      expect(summary.receivedCents, 0);
      expect(summary.spentCents, 0);
    });

    test('ten transactions of 0.10 sum to exactly 100 cents', () async {
      for (var i = 0; i < 10; i++) {
        await addExpense(10, d(2026, 10, 1 + i));
      }
      final summary = await txs.watchSummary(monthOf(2026, 10)).first;
      expect(summary.spentCents, 100);
    });

    test('watchTotalsUpTo includes today and excludes future dates', () async {
      await addIncome(5000, d(2026, 10, 10));
      await addExpense(1000, d(2026, 10, 10)); // today: counted
      await addExpense(777, d(2026, 10, 11)); // tomorrow: excluded
      await addIncome(888, d(2026, 12, 1)); // far future: excluded

      final totals = await txs.watchTotalsUpTo(d(2026, 10, 10)).first;
      expect(totals.receivedCents, 5000);
      expect(totals.spentCents, 1000);
    });

    test('summary stream updates when a transaction is added', () async {
      final emitted = <int>[];
      final sub = txs
          .watchSummary(monthOf(2026, 10))
          .listen((s) => emitted.add(s.spentCents));
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await addExpense(250, d(2026, 10, 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted.first, 0);
      expect(emitted.last, 250);
    });

    group('watchFiltered', () {
      setUp(() async {
        await addExpense(100, d(2026, 10, 1), category: food);
        await addExpense(300, d(2026, 10, 2), category: rent);
        await addIncome(200, d(2026, 10, 3));
        await addExpense(300, d(2026, 9, 20), category: food);
      });

      Future<List<int>> amounts({
        TransactionType? type,
        Set<int> categoryIds = const {},
        DateRange? range,
        SortOption sort = SortOption.newestFirst,
      }) async {
        final list = await txs
            .watchFiltered(
              type: type,
              categoryIds: categoryIds,
              range: range,
              sort: sort,
            )
            .first;
        return list.map((t) => t.transaction.amountCents).toList();
      }

      test('no filters returns everything, newest first', () async {
        expect(await amounts(), [200, 300, 100, 300]);
      });

      test('by type', () async {
        expect(await amounts(type: TransactionType.income), [200]);
        expect(await amounts(type: TransactionType.expense), [300, 100, 300]);
      });

      test('by categories (multi-select)', () async {
        expect(await amounts(categoryIds: {food.id}), [100, 300]);
        expect(await amounts(categoryIds: {food.id, rent.id}), [300, 100, 300]);
      });

      test('by range, null range means all time', () async {
        expect(await amounts(range: monthOf(2026, 10)), [200, 300, 100]);
        expect(await amounts(range: null), hasLength(4));
      });

      test('sorting', () async {
        expect(await amounts(sort: SortOption.oldestFirst), [
          300,
          100,
          300,
          200,
        ]);
        expect(await amounts(sort: SortOption.highestAmount), [
          300,
          300,
          200,
          100,
        ]);
        expect(await amounts(sort: SortOption.lowestAmount), [
          100,
          200,
          300,
          300,
        ]);
      });

      test('filters combine', () async {
        expect(
          await amounts(
            type: TransactionType.expense,
            categoryIds: {food.id},
            range: monthOf(2026, 10),
          ),
          [100],
        );
      });
    });

    test(
      'archived categories still resolve on existing transactions',
      () async {
        final id = await addExpense(500, d(2026, 10, 1), category: rent);
        await cats.archive(rent.id);

        final found = (await txs.getById(id))!;
        expect(found.category.name, 'Rent');
        expect(found.category.isArchived, isTrue);
      },
    );
  });

  group('CategoryRepository', () {
    test(
      'watchActive hides archived categories, watchAll shows them',
      () async {
        await cats.archive(rent.id);
        final active = await cats.watchActive(TransactionType.expense).first;
        final all = await cats.watchAll().first;

        expect(active.map((c) => c.name), isNot(contains('Rent')));
        expect(active.first.name, 'Food');
        expect(all.map((c) => c.name), contains('Rent'));

        await cats.restore(rent.id);
        final restored = await cats.watchActive(TransactionType.expense).first;
        expect(restored.map((c) => c.name), contains('Rent'));
      },
    );

    test('add trims whitespace and appends to the end of its type', () async {
      final tea = await cats.add('  Tea  ', TransactionType.expense);
      expect(tea.name, 'Tea');
      expect(tea.isDefault, isFalse);

      final active = await cats.watchActive(TransactionType.expense).first;
      expect(active.last.name, 'Tea');
    });

    test('add rejects empty names', () async {
      expect(
        () => cats.add('   ', TransactionType.expense),
        throwsA(isA<InvalidCategoryNameException>()),
      );
    });

    test('duplicates are rejected case-insensitively, per type', () async {
      expect(
        () => cats.add('food', TransactionType.expense),
        throwsA(isA<DuplicateCategoryException>()),
      );
      expect(
        () => cats.add(' FOOD ', TransactionType.expense),
        throwsA(isA<DuplicateCategoryException>()),
      );

      // Same name is fine under the other type.
      final income = await cats.add('Food', TransactionType.income);
      expect(income.type, TransactionType.income);
    });

    test(
      'duplicate of an archived category carries the archived match',
      () async {
        await cats.archive(rent.id);
        try {
          await cats.add('rent', TransactionType.expense);
          fail('should have thrown');
        } on DuplicateCategoryException catch (e) {
          expect(e.archivedMatch?.id, rent.id);
        }
      },
    );

    test('duplicate of an active category has no archived match', () async {
      try {
        await cats.add('Food', TransactionType.expense);
        fail('should have thrown');
      } on DuplicateCategoryException catch (e) {
        expect(e.archivedMatch, isNull);
      }
    });

    test(
      'rename works, applies the duplicate rule, and allows case change',
      () async {
        await cats.rename(food.id, 'Groceries');
        expect((await cats.getById(food.id))!.name, 'Groceries');

        expect(
          () => cats.rename(food.id, 'rent'),
          throwsA(isA<DuplicateCategoryException>()),
        );

        // Changing only the case of its own name is not a duplicate.
        await cats.rename(food.id, 'GROCERIES');
        expect((await cats.getById(food.id))!.name, 'GROCERIES');
      },
    );

    test(
      'add stores the chosen icon; the default is the general one',
      () async {
        final tea = await cats.add(
          'Tea',
          TransactionType.expense,
          icon: 'cafe',
        );
        expect(tea.icon, 'cafe');
        final plain = await cats.add('Misc', TransactionType.expense);
        expect(plain.icon, 'category');
      },
    );

    test('update changes name and icon together', () async {
      await cats.update(food.id, name: ' Groceries ', icon: 'groceries');
      final updated = (await cats.getById(food.id))!;
      expect(updated.name, 'Groceries');
      expect(updated.icon, 'groceries');
    });

    test('update only the icon (same name) is not a duplicate', () async {
      await cats.update(food.id, name: 'food', icon: 'fastfood');
      expect((await cats.getById(food.id))!.icon, 'fastfood');
    });

    test('update applies the duplicate and empty-name rules', () async {
      expect(
        () => cats.update(food.id, name: 'Rent', icon: 'home'),
        throwsA(isA<DuplicateCategoryException>()),
      );
      expect(
        () => cats.update(food.id, name: '  ', icon: 'home'),
        throwsA(isA<InvalidCategoryNameException>()),
      );
      expect(
        (await cats.getById(food.id))!.name,
        'Food',
        reason: 'nothing changed',
      );
    });

    test('"Other" can change its icon but not its name', () async {
      final all = await cats.watchAll().first;
      final other = all.firstWhere(
        (c) => c.name == 'Other' && c.type == TransactionType.expense,
      );
      await cats.update(other.id, name: 'Other', icon: 'star');
      expect((await cats.getById(other.id))!.icon, 'star');
      expect(
        () => cats.update(other.id, name: 'Misc', icon: 'star'),
        throwsA(isA<ProtectedCategoryException>()),
      );
    });

    test('"Other" cannot be archived or renamed', () async {
      final all = await cats.watchAll().first;
      final others = all.where((c) => c.name == 'Other').toList();
      expect(others, hasLength(2));

      for (final other in others) {
        expect(
          () => cats.archive(other.id),
          throwsA(isA<ProtectedCategoryException>()),
        );
        expect(
          () => cats.rename(other.id, 'Misc'),
          throwsA(isA<ProtectedCategoryException>()),
        );
      }
    });
  });
}
