import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
import '../domain/budget.dart';
import '../domain/trends.dart';
import 'budget_providers.dart';
import 'database_providers.dart';
import 'period_providers.dart';

/// How many months the Trends page shows (6 or 12).
final trendWindowProvider = NotifierProvider<TrendWindow, int>(TrendWindow.new);

class TrendWindow extends Notifier<int> {
  @override
  int build() => trendWindows.first;

  void set(int months) {
    if (trendWindows.contains(months)) state = months;
  }
}

/// A number that changes whenever a transaction does. The Trends figures are
/// worked out again when it moves, instead of each month watching its own
/// stream.
final _changesProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchChangeCount(),
);

/// Received and Spent for each of the last [count] budget months, oldest
/// first, the month under way last.
final trendTotalsProvider = FutureProvider.family<List<MonthTotals>, int>((
  ref,
  count,
) async {
  await ref.watch(_changesProvider.future);
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  final months = trendMonths(today, count, startDay);
  final sums = await ref.read(transactionRepositoryProvider).summariesForRanges(
    [for (final m in months) m.range(startDay)],
  );
  return monthTotalsOf(months, sums, today, startDay);
});

/// What one category (null: all spending) spent in each of the last [count]
/// budget months, oldest first, in the same order as [trendTotalsProvider].
final trendCategorySeriesProvider =
    FutureProvider.family<List<int>, ({int? categoryId, int count})>((
      ref,
      key,
    ) async {
      await ref.watch(_changesProvider.future);
      final today = ref.watch(clockProvider);
      final startDay = ref.watch(monthStartDayProvider);
      final months = trendMonths(today, key.count, startDay);
      return ref.read(transactionRepositoryProvider).spentForKeys([
        for (final m in months) (m.range(startDay), key.categoryId),
      ]);
    });

/// The categories that spent most over the last [count] months, biggest first
/// (at most five): the ones offered for "a category over time".
final trendCategoryChoicesProvider =
    FutureProvider.family<List<CategoryHistory>, int>((ref, count) async {
      await ref.watch(_changesProvider.future);
      final today = ref.watch(clockProvider);
      final startDay = ref.watch(monthStartDayProvider);
      final ranges = [
        for (final m in trendMonths(today, count, startDay)) m.range(startDay),
      ];
      final all = await ref
          .read(transactionRepositoryProvider)
          .categoryHistoryForRanges(ranges);
      int total(CategoryHistory h) => h.spent.fold<int>(0, (a, b) => a + b);
      all.sort((a, b) => total(b).compareTo(total(a)));
      return all.take(5).toList();
    });

/// The categories that moved most in the last finished month against the
/// three before it.
class TrendMovers {
  const TrendMovers({
    required this.month,
    required this.up,
    required this.down,
    required this.monthsAveraged,
  });

  final BudgetMonth month;
  final List<CategoryMove> up;
  final List<CategoryMove> down;
  final int monthsAveraged;
}

/// Null while there is too little history to say anything (fewer than two
/// earlier months with something logged).
final trendMoversProvider = FutureProvider<TrendMovers?>((ref) async {
  final totals = await ref.watch(trendTotalsProvider(6).future);
  final startDay = ref.watch(monthStartDayProvider);
  final finished = [
    for (final t in totals)
      if (!t.inProgress) t,
  ];
  if (finished.length < 3) return null;
  final last = finished.last;
  // Up to three months before it, newest first, without the empty ones that
  // lie before anything was logged.
  final earlier = finished.reversed.skip(1).take(3).toList();
  while (earlier.isNotEmpty && earlier.last.isEmpty) {
    earlier.removeLast();
  }
  if (earlier.where((t) => !t.isEmpty).length < 2) return null;
  final histories = await ref
      .read(transactionRepositoryProvider)
      .categoryHistoryForRanges([
        last.month.range(startDay),
        for (final t in earlier) t.month.range(startDay),
      ]);
  final movers = topMovers(histories);
  return TrendMovers(
    month: last.month,
    up: movers.up,
    down: movers.down,
    monthsAveraged: earlier.length,
  );
});

/// The month under way so far: how spending ran, and its biggest expense.
class TrendRecords {
  const TrendRecords({required this.rhythm, this.biggest});

  final SpendingRhythm rhythm;
  final TransactionWithCategory? biggest;
}

/// Null before the month has begun or when nothing was spent in it.
final trendRecordsProvider = FutureProvider<TrendRecords?>((ref) async {
  await ref.watch(_changesProvider.future);
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  final range = BudgetMonth.containing(today, startDay).range(startDay);
  final repo = ref.read(transactionRepositoryProvider);
  final byDay = await repo.expenseByDay(range);
  final rhythm = rhythmOf(byDay, range, today);
  if (rhythm == null || rhythm.totalCents == 0) return null;
  final top = await repo.topExpenses(range, limit: 1);
  return TrendRecords(rhythm: rhythm, biggest: top.firstOrNull);
});

/// Reads every Trends figure again (the page's "Try again").
void reloadTrends(WidgetRef ref) {
  ref.invalidate(trendTotalsProvider);
  ref.invalidate(trendCategorySeriesProvider);
  ref.invalidate(trendCategoryChoicesProvider);
  ref.invalidate(trendMoversProvider);
  ref.invalidate(trendRecordsProvider);
}
