import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/domain/week_mode.dart';
import 'package:heisenbudget/providers/category_providers.dart';
import 'package:heisenbudget/providers/database_providers.dart';
import 'package:heisenbudget/providers/history_providers.dart';
import 'package:heisenbudget/providers/period_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:heisenbudget/providers/transaction_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// Lets drift streams and provider rebuilds deliver their next value.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.memory();
    now = d(2026, 10, 15); // a Thursday
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        nowProvider.overrideWithValue(() => now),
      ],
    );
    // Riverpod 3 disposes providers nobody listens to, which would make
    // `.future` reads in the helpers below hang.
    container.listen(allCategoriesProvider, (_, next) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Keeps a provider alive so it keeps receiving stream updates.
  void keepAlive(ProviderListenable<Object?> provider) {
    container.listen(provider, (_, next) {});
  }

  Future<int> categoryId(String name, TransactionType type) async {
    final all = await container.read(allCategoriesProvider.future);
    return all.firstWhere((c) => c.name == name && c.type == type).id;
  }

  Future<void> addTx(
    int cents,
    DateTime date, {
    TransactionType type = TransactionType.expense,
  }) async {
    final category = await categoryId(
      type == TransactionType.expense ? 'Food' : 'Salary',
      type,
    );
    await container
        .read(transactionRepositoryProvider)
        .add(
          TransactionInput(
            amountCents: cents,
            type: type,
            date: date,
            categoryId: category,
          ),
        );
  }

  group('balance and summaries', () {
    test(
      'inserting a transaction updates balance and period summary',
      () async {
        keepAlive(balanceProvider);
        keepAlive(periodSummaryProvider);
        expect(await container.read(balanceProvider.future), 0);

        await addTx(100000, d(2026, 10, 1), type: TransactionType.income);
        await addTx(2500, d(2026, 10, 2));
        await settle();

        expect(container.read(balanceProvider).value, 97500);
        final summary = container.read(periodSummaryProvider).value!;
        expect(summary.receivedCents, 100000);
        expect(summary.spentCents, 2500);
        expect(summary.netCents, 97500);
      },
    );

    test('the balance is income minus expenses and can go negative', () async {
      keepAlive(balanceProvider);
      await addTx(1000, d(2026, 10, 2), type: TransactionType.income);
      await addTx(5000, d(2026, 10, 3));
      await settle();
      expect(container.read(balanceProvider).value, -4000);
    });

    test('future-dated transactions are excluded from the balance', () async {
      keepAlive(balanceProvider);
      await addTx(1000, d(2026, 10, 15), type: TransactionType.income); // today
      await addTx(400, d(2026, 10, 16)); // tomorrow
      await settle();
      expect(container.read(balanceProvider).value, 1000);
    });

    test('balance picks up a new day after the clock refreshes', () async {
      keepAlive(balanceProvider);
      await addTx(1000, d(2026, 10, 15), type: TransactionType.income);
      await addTx(400, d(2026, 10, 16));
      await settle();
      expect(container.read(balanceProvider).value, 1000);

      now = d(2026, 10, 16);
      container.read(clockProvider.notifier).refresh();
      await settle();
      expect(container.read(balanceProvider).value, 600);
    });

    test('balance ignores the selected period', () async {
      keepAlive(balanceProvider);
      await addTx(1000, d(2026, 9, 1), type: TransactionType.income);
      await settle();
      // The selected period is October, but the balance counts September too.
      expect(container.read(balanceProvider).value, 1000);
    });

    test('recent transactions are the last 3 in the selected range', () async {
      keepAlive(recentTransactionsProvider);
      for (var day = 1; day <= 7; day++) {
        await addTx(100 * day, d(2026, 10, day));
      }
      await addTx(9999, d(2026, 9, 30)); // outside October
      await settle();

      final recent = container.read(recentTransactionsProvider).value!;
      expect(recent.map((t) => t.transaction.amountCents), [700, 600, 500]);
    });
  });

  group('periods and week settings', () {
    test('default period is this month', () {
      expect(container.read(periodRangeProvider), monthOf(2026, 10));
    });

    test(
      'switching week mode or week start day changes the week range',
      () async {
        container.read(selectedPeriodProvider.notifier).select(ThisWeek(now));
        // Thursday Oct 15, Monday start.
        expect(
          container.read(periodRangeProvider),
          DateRange(d(2026, 10, 12), d(2026, 10, 18)),
        );

        await container.read(settingsProvider.notifier).setWeekStartDay(7);
        expect(
          container.read(periodRangeProvider),
          DateRange(d(2026, 10, 11), d(2026, 10, 17)),
        );

        await container
            .read(settingsProvider.notifier)
            .setWeekMode(WeekMode.fixed);
        // Fixed block containing day 15 is 15-21.
        expect(
          container.read(periodRangeProvider),
          DateRange(d(2026, 10, 15), d(2026, 10, 21)),
        );
      },
    );

    test('Week N of a month follows the week settings', () async {
      container
          .read(selectedPeriodProvider.notifier)
          .select(const WeekOfMonth(2026, 10, 1));
      expect(
        container.read(periodRangeProvider),
        DateRange(d(2026, 10, 1), d(2026, 10, 4)),
      );

      await container
          .read(settingsProvider.notifier)
          .setWeekMode(WeekMode.fixed);
      expect(
        container.read(periodRangeProvider),
        DateRange(d(2026, 10, 1), d(2026, 10, 7)),
      );
    });

    test(
      'selected Week N is clamped when settings leave it out of range',
      () async {
        // Aug 2026 has 6 Monday-start weeks, 5 fixed blocks.
        container
            .read(selectedPeriodProvider.notifier)
            .select(const WeekOfMonth(2026, 8, 6));
        await container
            .read(settingsProvider.notifier)
            .setWeekMode(WeekMode.fixed);

        final period = container.read(selectedPeriodProvider) as WeekOfMonth;
        expect(period.n, 5);
        expect(
          container.read(periodRangeProvider),
          DateRange(d(2026, 8, 29), d(2026, 8, 31)),
        );
      },
    );

    test('stepping moves the month / week', () {
      final notifier = container.read(selectedPeriodProvider.notifier);
      notifier.step(1);
      expect(container.read(periodRangeProvider), monthOf(2026, 11));
      notifier.step(-2);
      expect(container.read(periodRangeProvider), monthOf(2026, 9));

      notifier.select(ThisWeek(now));
      notifier.step(1);
      expect(
        container.read(periodRangeProvider),
        DateRange(d(2026, 10, 19), d(2026, 10, 25)),
      );
    });

    test('the summary follows the selected period', () async {
      keepAlive(periodSummaryProvider);
      await addTx(500, d(2026, 10, 2));
      await addTx(700, d(2026, 11, 2));
      await settle();
      expect(container.read(periodSummaryProvider).value!.spentCents, 500);

      container.read(selectedPeriodProvider.notifier).step(1);
      await settle();
      expect(container.read(periodSummaryProvider).value!.spentCents, 700);
    });
  });

  group('categories', () {
    test(
      'active categories hide archived ones, all categories keep them',
      () async {
        keepAlive(activeCategoriesProvider(TransactionType.expense));
        keepAlive(allCategoriesProvider);
        final rent = await categoryId('Rent', TransactionType.expense);

        await container.read(categoryRepositoryProvider).archive(rent);
        await settle();

        final active = container
            .read(activeCategoriesProvider(TransactionType.expense))
            .value!;
        final all = container.read(allCategoriesProvider).value!;
        expect(active.map((c) => c.name), isNot(contains('Rent')));
        expect(all.map((c) => c.name), contains('Rent'));
      },
    );
  });

  group('history', () {
    Future<void> seed() async {
      final food = await categoryId('Food', TransactionType.expense);
      final rent = await categoryId('Rent', TransactionType.expense);
      final repo = container.read(transactionRepositoryProvider);
      Future<void> add(
        int cents,
        DateTime date,
        int category, [
        TransactionType type = TransactionType.expense,
      ]) async {
        await repo.add(
          TransactionInput(
            amountCents: cents,
            type: type,
            date: date,
            categoryId: category,
          ),
        );
      }

      await add(100, d(2026, 10, 1), food);
      await add(300, d(2026, 10, 2), rent);
      await add(
        200,
        d(2026, 10, 3),
        await categoryId('Salary', TransactionType.income),
        TransactionType.income,
      );
      await add(300, d(2026, 9, 20), food);
    }

    List<int> amounts() => container
        .read(historyListProvider)
        .value!
        .map((t) => t.transaction.amountCents)
        .toList();

    test('defaults to everything, newest first', () async {
      keepAlive(historyListProvider);
      await seed();
      await settle();
      expect(amounts(), [200, 300, 100, 300]);
      expect(container.read(historyFilterProvider).hasFilters, isFalse);
    });

    test('type, category, period and sort work alone and combined', () async {
      keepAlive(historyListProvider);
      await seed();
      final food = await categoryId('Food', TransactionType.expense);
      final notifier = container.read(historyFilterProvider.notifier);

      notifier.setType(TransactionType.expense);
      await settle();
      expect(amounts(), [300, 100, 300]);

      notifier.setCategories({food});
      await settle();
      expect(amounts(), [100, 300]);

      notifier.setPeriod(ThisMonth(now));
      await settle();
      expect(amounts(), [100]);

      notifier.clear();
      notifier.setSort(SortOption.lowestAmount);
      await settle();
      expect(amounts(), [100, 200, 300, 300]);
      notifier.setSort(SortOption.highestAmount);
      await settle();
      expect(amounts(), [300, 300, 200, 100]);
      notifier.setSort(SortOption.oldestFirst);
      await settle();
      expect(amounts(), [300, 100, 300, 200]);
    });

    test('clear removes filters but keeps the sort', () async {
      final notifier = container.read(historyFilterProvider.notifier);
      notifier.setType(TransactionType.income);
      notifier.setSort(SortOption.highestAmount);
      expect(container.read(historyFilterProvider).hasFilters, isTrue);

      notifier.clear();
      final filter = container.read(historyFilterProvider);
      expect(filter.hasFilters, isFalse);
      expect(filter.sort, SortOption.highestAmount);
    });

    test('history period follows the week settings', () async {
      keepAlive(historyListProvider);
      await seed();
      container
          .read(historyFilterProvider.notifier)
          .setPeriod(const WeekOfMonth(2026, 10, 1));
      await settle();
      // Calendar, Monday start: Week 1 of Oct 2026 is Oct 1-4 -> 3 items.
      expect(amounts(), [200, 300, 100]);

      await container
          .read(settingsProvider.notifier)
          .setWeekMode(WeekMode.fixed);
      await settle();
      // Fixed Week 1 is Oct 1-7: same 3 items; Week 3 would be empty.
      expect(amounts(), [200, 300, 100]);
    });
  });
}
