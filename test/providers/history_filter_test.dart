import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/saved_filter.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/providers/history_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;
  final today = DateTime(2026, 10, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'currency_code': 'USD'});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsRepository(prefs, defaultCurrency: 'USD').load();
  });

  group('what counts as a filter', () {
    test(
      'the amount range and a date jump narrow the list and are counted',
      () {
        const none = HistoryFilter();
        expect((none.hasFilters, none.activeCount), (false, 0));

        final amount = none.withAmountRange(500, null);
        expect((amount.hasFilters, amount.hasAmountRange), (true, true));
        expect(amount.activeCount, 1, reason: 'one range is one filter');
        expect(none.withAmountRange(null, 900).hasAmountRange, isTrue);
        expect(amount.withAmountRange(null, null).hasFilters, isFalse);

        final jumped = none.withJump(DateTime(2026, 3, 9, 17, 30));
        expect(jumped.jumpTo, DateTime(2026, 3, 9), reason: 'date only');
        expect((jumped.hasFilters, jumped.activeCount), (true, 1));

        final all = HistoryFilter(
          type: TransactionType.expense,
          categoryIds: const {1, 2},
          period: ThisMonth(today),
          minCents: 1,
          maxCents: 2,
          jumpTo: DateTime(2026, 10, 5),
        );
        expect(all.activeCount, 1 + 2 + 1 + 1 + 1);
      },
    );

    test('clearing removes them too but keeps the sort and the search', () {
      final f = HistoryFilter(
        minCents: 100,
        jumpTo: DateTime(2026, 10, 1),
        sort: SortOption.oldestFirst,
        query: 'tea',
      ).cleared();
      expect(f.hasFilters, isFalse);
      expect((f.sort, f.query), (SortOption.oldestFirst, 'tea'));
    });

    test('a new period drops the jump; sorting by amount drops it too', () {
      final f = HistoryFilter(jumpTo: DateTime(2026, 10, 1));
      expect(f.withPeriod(ThisMonth(today)).jumpTo, isNull);
      expect(f.withSort(SortOption.highestAmount).jumpTo, isNull);
      expect(f.withSort(SortOption.oldestFirst).jumpTo, DateTime(2026, 10, 1));
      expect(f.withType(TransactionType.income).jumpTo, isNotNull);
    });
  });

  group('the dates History reads', () {
    DateRange? range(HistoryFilter f) => historyRangeOf(f, settings);

    test('no period and no jump is all time', () {
      expect(range(const HistoryFilter()), isNull);
    });

    test('the period alone is that period', () {
      expect(
        range(HistoryFilter(period: ThisMonth(today))),
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
    });

    test('newest first: a jump becomes the last day shown', () {
      final r = range(HistoryFilter(jumpTo: DateTime(2026, 3, 9)))!;
      expect(r.end, DateTime(2026, 3, 9));
      expect(r.start.year, 1900);

      final inMonth = range(
        HistoryFilter(period: ThisMonth(today), jumpTo: DateTime(2026, 10, 9)),
      );
      expect(inMonth, DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 9)));
    });

    test('oldest first: a jump becomes the first day shown', () {
      final r = range(
        HistoryFilter(
          jumpTo: DateTime(2026, 3, 9),
          sort: SortOption.oldestFirst,
        ),
      )!;
      expect(r.start, DateTime(2026, 3, 9));
      expect(r.end.year, 2999);

      final inMonth = range(
        HistoryFilter(
          period: ThisMonth(today),
          jumpTo: DateTime(2026, 10, 9),
          sort: SortOption.oldestFirst,
        ),
      );
      expect(inMonth, DateRange(DateTime(2026, 10, 9), DateTime(2026, 10, 31)));
    });

    test('a jump that cannot be followed shows the period instead', () {
      final month = ThisMonth(today);
      expect(
        range(HistoryFilter(period: month, jumpTo: DateTime(2026, 9, 1))),
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
    });

    test('sorted by amount a jump is ignored', () {
      expect(
        range(
          HistoryFilter(
            jumpTo: DateTime(2026, 3, 9),
            sort: SortOption.lowestAmount,
          ),
        ),
        isNull,
      );
    });
  });

  group('saved filters', () {
    test('a filter becomes a saved one and comes back as it was', () {
      final filter = HistoryFilter(
        type: TransactionType.expense,
        categoryIds: const {4, 7},
        period: ThisMonth(today),
        minCents: 1000,
        maxCents: 90000,
        sort: SortOption.highestAmount,
        query: 'not kept',
        jumpTo: DateTime(2026, 10, 9),
      );
      final saved = savedFilterOf(filter, '  Big spending ', settings, today);
      expect(saved.name, 'Big spending');
      expect(saved.period, SavedPeriod.thisMonth, reason: 'relative');

      final back = historyFilterOf(saved, today);
      expect(back.type, TransactionType.expense);
      expect(back.categoryIds, {4, 7});
      expect((back.minCents, back.maxCents), (1000, 90000));
      expect(back.sort, SortOption.highestAmount);
      expect(back.query, isEmpty, reason: 'the search is not saved');
      expect(back.jumpTo, isNull, reason: 'neither is a jump');
      expect(
        historyRangeOf(back, settings),
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
    });

    test('"this month" saved now means the month of the day it is used', () {
      final saved = savedFilterOf(
        HistoryFilter(period: ThisMonth(today)),
        'm',
        settings,
        today,
      );
      final later = historyFilterOf(saved, DateTime(2027, 2, 3));
      expect(
        historyRangeOf(later, settings),
        DateRange(DateTime(2027, 2, 1), DateTime(2027, 2, 28)),
      );
    });

    test('a fixed range is kept as the dates it covers', () {
      final period = Custom(DateTime(2026, 1, 5), DateTime(2026, 2, 6));
      final saved = savedFilterOf(
        HistoryFilter(period: period),
        'q1ish',
        settings,
        today,
      );
      expect(saved.period, SavedPeriod.custom);
      expect(saved.customStart, DateTime(2026, 1, 5));
      expect(saved.customEnd, DateTime(2026, 2, 6));
      expect(
        historyRangeOf(historyFilterOf(saved, DateTime(2030, 1, 1)), settings),
        DateRange(DateTime(2026, 1, 5), DateTime(2026, 2, 6)),
      );
    });

    test('all time stays all time', () {
      final saved = savedFilterOf(
        const HistoryFilter(minCents: 5),
        'a',
        settings,
        today,
      );
      expect(saved.period, SavedPeriod.allTime);
      expect(historyFilterOf(saved, today).period, isNull);
    });
  });
}
