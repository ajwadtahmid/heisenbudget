import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/saved_filter.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/domain/week_mode.dart';

void main() {
  final today = DateTime(2026, 10, 15);

  group('JSON', () {
    test('a full filter survives the round trip', () {
      final filter = SavedFilter(
        name: 'Big food',
        type: TransactionType.expense,
        categoryIds: {3, 1},
        period: SavedPeriod.custom,
        customStart: DateTime(2026, 1, 1),
        customEnd: DateTime(2026, 3, 31),
        minCents: 2000,
        maxCents: 50000,
        sort: SortOption.highestAmount,
      );
      final back = SavedFilter.fromJson(filter.toJson())!;
      expect(back.name, 'Big food');
      expect(back.type, TransactionType.expense);
      expect(back.categoryIds, {1, 3});
      expect(back.period, SavedPeriod.custom);
      expect(back.customStart, DateTime(2026, 1, 1));
      expect(back.customEnd, DateTime(2026, 3, 31));
      expect((back.minCents, back.maxCents), (2000, 50000));
      expect(back.sort, SortOption.highestAmount);
    });

    test('a bare filter needs only a name and a period', () {
      final f = SavedFilter.fromJson({
        'name': ' Everything ',
        'categoryIds': <int>[],
        'period': 'allTime',
      })!;
      expect(f.name, 'Everything', reason: 'trimmed');
      expect(f.type, isNull);
      expect(f.sort, SortOption.newestFirst, reason: 'the default');
    });

    test('anything unusable is refused', () {
      Map<String, Object?> good() => {
        'name': 'Ok',
        'categoryIds': [1],
        'period': 'thisMonth',
      };
      final bad = <String, Map<String, Object?>>{
        'no name': good()..remove('name'),
        'blank name': good()..['name'] = '   ',
        'long name': good()..['name'] = 'x' * 41,
        'name not text': good()..['name'] = 5,
        'unknown type': good()..['type'] = 'transfer',
        'ids not a list': good()..['categoryIds'] = 'all',
        'id not an int': good()..['categoryIds'] = ['a'],
        'id below 1': good()..['categoryIds'] = [0],
        'too many ids': good()
          ..['categoryIds'] = List.generate(501, (i) => i + 1),
        'unknown period': good()..['period'] = 'yesterday',
        'custom without dates': good()..['period'] = 'custom',
        'custom dates not real': good()
          ..['period'] = 'custom'
          ..['start'] = '2026-02-31'
          ..['end'] = '2026-03-01',
        'custom dates reversed': good()
          ..['period'] = 'custom'
          ..['start'] = '2026-05-01'
          ..['end'] = '2026-04-01',
        'custom date before 1900': good()
          ..['period'] = 'custom'
          ..['start'] = '1899-12-31'
          ..['end'] = '2026-01-01',
        'min not a number': good()..['minCents'] = '5',
        'min zero': good()..['minCents'] = 0,
        'max too large': good()..['maxCents'] = 99999999999 + 1,
        'min above max': good()
          ..['minCents'] = 500
          ..['maxCents'] = 100,
      };
      for (final entry in bad.entries) {
        expect(SavedFilter.fromJson(entry.value), isNull, reason: entry.key);
      }
      expect(SavedFilter.fromJson('not a map'), isNull);
      expect(SavedFilter.fromJson(null), isNull);
      expect(SavedFilter.fromJson(good()), isNotNull);
    });

    test('an unknown sort falls back instead of refusing the filter', () {
      final f = SavedFilter.fromJson({
        'name': 'Ok',
        'categoryIds': <int>[],
        'period': 'allTime',
        'sort': 'sideways',
      })!;
      expect(f.sort, SortOption.newestFirst);
    });

    test(
      'a list keeps the usable ones, drops repeats and stops at the cap',
      () {
        final list = SavedFilter.listFromJson([
          {'name': 'One', 'categoryIds': <int>[], 'period': 'allTime'},
          'junk',
          {
            'name': 'one',
            'categoryIds': [2],
            'period': 'allTime',
          }, // same name
          {'name': 'Two', 'categoryIds': <int>[], 'period': 'thisWeek'},
        ]);
        expect(list.map((f) => f.name), ['One', 'Two']);
        expect(list.first.categoryIds, isEmpty, reason: 'the first one wins');

        final many = SavedFilter.listFromJson([
          for (var i = 0; i < 30; i++)
            {'name': 'F$i', 'categoryIds': <int>[], 'period': 'allTime'},
        ]);
        expect(many, hasLength(maxSavedFilters));
        expect(SavedFilter.listFromJson('nope'), isEmpty);
      },
    );
  });

  group('periods', () {
    SavedPeriod kind(Period? p) =>
        SavedFilter.kindOf(p, today, WeekMode.calendar, 1);

    test('this week and this and last month are kept as relative', () {
      expect(kind(null), SavedPeriod.allTime);
      expect(kind(ThisWeek(today)), SavedPeriod.thisWeek);
      expect(kind(ThisWeek(DateTime(2026, 10, 13))), SavedPeriod.thisWeek);
      expect(kind(ThisMonth(today)), SavedPeriod.thisMonth);
      expect(kind(ThisMonth(DateTime(2026, 10, 1))), SavedPeriod.thisMonth);
      expect(kind(ThisMonth(DateTime(2026, 9, 3))), SavedPeriod.lastMonth);
    });

    test('anything else is kept as the dates it covers', () {
      expect(kind(ThisWeek(DateTime(2026, 9, 1))), SavedPeriod.custom);
      expect(kind(ThisMonth(DateTime(2026, 7, 1))), SavedPeriod.custom);
      expect(kind(const WeekOfMonth(2026, 10, 2)), SavedPeriod.custom);
      expect(
        kind(Custom(DateTime(2026, 1, 1), DateTime(2026, 2, 1))),
        SavedPeriod.custom,
      );
    });

    test('a relative period means "now" when it is used', () {
      const thisMonthFilter = SavedFilter(
        name: 'm',
        period: SavedPeriod.thisMonth,
      );
      final inMarch =
          thisMonthFilter.periodFor(DateTime(2027, 3, 9)) as ThisMonth;
      expect(inMarch.anchor, DateTime(2027, 3, 9));

      const last = SavedFilter(name: 'l', period: SavedPeriod.lastMonth);
      final lm = last.periodFor(DateTime(2027, 1, 20)) as ThisMonth;
      expect((lm.anchor.year, lm.anchor.month), (2026, 12));

      expect(const SavedFilter(name: 'a').periodFor(today), isNull);
      final custom = SavedFilter(
        name: 'c',
        period: SavedPeriod.custom,
        customStart: DateTime(2026, 1, 1),
        customEnd: DateTime(2026, 2, 1),
      ).periodFor(today) as Custom;
      expect(custom.range.start, DateTime(2026, 1, 1));
    });
  });

  group('upsert', () {
    SavedFilter named(String n) => SavedFilter(name: n);

    test('adds a new name at the end', () {
      final out = SavedFilter.upsert([named('A')], named('B'))!;
      expect(out.map((f) => f.name), ['A', 'B']);
    });

    test('a name already kept (any case) is replaced, not repeated', () {
      final replacement = SavedFilter(name: 'a', minCents: 100);
      final out = SavedFilter.upsert([named('A'), named('B')], replacement)!;
      expect(out.map((f) => f.name), ['a', 'B']);
      expect(out.first.minCents, 100);
    });

    test('a full list refuses a new name but still replaces', () {
      final full = [for (var i = 0; i < maxSavedFilters; i++) named('F$i')];
      expect(SavedFilter.upsert(full, named('New')), isNull);
      expect(SavedFilter.upsert(full, named('f3')), hasLength(maxSavedFilters));
    });
  });
}
