import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/budget.dart';
import '../domain/date_range.dart';
import '../domain/transaction_type.dart';
import 'category_providers.dart';
import 'database_providers.dart';
import 'period_providers.dart';
import 'recurring_providers.dart';
import 'settings_providers.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(appDatabaseProvider)),
);

/// Every stored limit row.
final budgetLimitsProvider = StreamProvider<List<BudgetLimitRow>>((ref) {
  return ref.watch(budgetRepositoryProvider).watchAll();
});

/// The day budget months start on (1 to 28).
final monthStartDayProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider.select((s) => s.monthStartDay)),
);

/// The weekday weeks start on (1 = Monday to 7 = Sunday). Weekly and
/// every-two-weeks budgets use it whatever the Home period menu is set to.
final weekStartDayProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider.select((s) => s.weekStartDay)),
);

/// Expenses inside a range for one category (or, with null, all of them).
final _spentProvider = StreamProvider.family<int, (DateRange, int?)>(
  (ref, key) => ref
      .watch(transactionRepositoryProvider)
      .watchSpentInRange(key.$1, categoryId: key.$2),
);

/// One budget on screen: a category's, or all spending's (no category).
class BudgetLine {
  const BudgetLine({
    required this.categoryId,
    required this.category,
    required this.entry,
    required this.range,
    required this.status,
  });

  final int? categoryId;
  final CategoryRow? category;

  /// The row in force: its period and whether it repeats.
  final LimitEntry entry;

  /// The current period.
  final DateRange range;
  final BudgetStatus status;

  bool get isOverall => categoryId == null;
  BudgetUnit get unit => entry.unit;
}

/// Every budget in force today.
class BudgetOverview {
  const BudgetOverview({
    required this.overall,
    required this.lines,
    required this.withoutLimit,
    required this.sameUnitCategoryTotal,
  });

  /// The limit on all spending, if there is one.
  final BudgetLine? overall;

  /// Categories that have a budget, the ones in trouble first.
  final List<BudgetLine> lines;

  /// Expense categories with no budget now.
  final List<CategoryRow> withoutLimit;

  /// The category limits that use the same period as the overall one, added up
  /// (comparing a week with a month would mean nothing).
  final int sameUnitCategoryTotal;

  bool get hasAny => overall != null || lines.isNotEmpty;

  bool get categoriesExceedOverall =>
      overall != null && sameUnitCategoryTotal > overall!.status.limit;

  Iterable<BudgetLine> get all => [?overall, ...lines];

  int get overCount =>
      all.where((l) => l.status.level == BudgetLevel.over).length;

  int get almostCount =>
      all.where((l) => l.status.level == BudgetLevel.almost).length;
}

/// The budgets in force today, with how each is doing. Null until the
/// spending for each has loaded.
final budgetOverviewProvider = Provider<BudgetOverview?>((ref) {
  final limits = ref.watch(budgetLimitsProvider).value;
  final categories = ref.watch(allCategoriesProvider).value;
  final rules = ref.watch(recurringRulesProvider).value ?? const [];
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  if (limits == null || categories == null) return null;

  final entries = [for (final row in limits) row.entry];
  final plannedRules = [
    for (final rule in rules)
      if (rule.isActive && rule.type == TransactionType.expense)
        PlannedRule(
          categoryId: rule.categoryId,
          amountCents: rule.amountCents,
          recurrence: rule.recurrence,
          nextIndex: rule.nextIndex,
        ),
  ];

  // Null means a spending figure is still loading.
  BudgetLine? line(int? categoryId, CategoryRow? category) {
    final resolved = resolveBudget(
      entries,
      categoryId,
      today,
      monthStartDay: startDay,
    );
    if (resolved == null) return null;
    final spent = ref.watch(_spentProvider((resolved.range, categoryId))).value;
    if (spent == null) throw _Loading();
    final planned = plannedByCategory(plannedRules, resolved.range, today);
    final plannedCents = categoryId == null
        ? planned.values.fold<int>(0, (a, b) => a + b)
        : planned[categoryId] ?? 0;
    return BudgetLine(
      categoryId: categoryId,
      category: category,
      entry: resolved.entry,
      range: resolved.range,
      status: buildBudgetStatus(
        limit: resolved.limit,
        spent: spent,
        planned: plannedCents,
        range: resolved.range,
        today: today,
      ),
    );
  }

  try {
    final overall = line(null, null);
    final lines = <BudgetLine>[];
    final withoutLimit = <CategoryRow>[];
    for (final category in categories) {
      if (category.type != TransactionType.expense) continue;
      final l = line(category.id, category);
      if (l == null) {
        if (!category.isArchived) withoutLimit.add(category);
      } else {
        lines.add(l);
      }
    }
    // Worst first: over, then almost, then by how much of the limit is used.
    lines.sort((a, b) {
      final byLevel = b.status.level.index.compareTo(a.status.level.index);
      if (byLevel != 0) return byLevel;
      final byShare = b.status.permille.compareTo(a.status.permille);
      return byShare != 0
          ? byShare
          : a.category!.name.compareTo(b.category!.name);
    });
    final sameUnit = overall == null
        ? 0
        : lines
              .where((l) => l.unit == overall.unit)
              .fold<int>(0, (a, l) => a + l.status.limit);
    return BudgetOverview(
      overall: overall,
      lines: lines,
      withoutLimit: withoutLimit,
      sameUnitCategoryTotal: sameUnit,
    );
  } on _Loading {
    return null;
  }
});

class _Loading implements Exception {}

/// What Home says about budgets.
class BudgetSummary {
  const BudgetSummary({required this.over, required this.almost});

  final int over;
  final int almost;
}

/// Null when no budget is in force (Home then shows nothing).
final budgetSummaryProvider = Provider<BudgetSummary?>((ref) {
  final overview = ref.watch(budgetOverviewProvider);
  if (overview == null || !overview.hasAny) return null;
  return BudgetSummary(over: overview.overCount, almost: overview.almostCount);
});

/// A suggested limit: the average of what was spent in the three periods
/// before [current] (of [unit]), for one category or (null) all spending.
/// Null when nothing was spent in them.
Future<int?> suggestedLimit({
  required TransactionRepository repo,
  required BudgetUnit unit,
  required DateRange current,
  required int monthStartDay,
  int? categoryId,
}) async {
  final spends = <int>[];
  var range = current;
  for (var back = 1; back <= 3; back++) {
    range = previousRange(range, unit, monthStartDay);
    spends.add(await repo.spentInRange(range, categoryId: categoryId));
  }
  return suggestLimit(spends);
}

/// How a finished budget period ended.
enum BudgetResult { within, usedAll, over }

/// One finished period of one budget, with what was spent.
class PastBudget {
  const PastBudget({
    required this.categoryId,
    required this.category,
    required this.entry,
    required this.range,
    required this.limit,
    required this.spent,
  });

  final int? categoryId;
  final CategoryRow? category;
  final LimitEntry entry;
  final DateRange range;
  final int limit;
  final int spent;

  BudgetUnit get unit => entry.unit;
  bool get isOneTime => !entry.repeats;

  BudgetResult get result => spent > limit
      ? BudgetResult.over
      : spent == limit
      ? BudgetResult.usedAll
      : BudgetResult.within;

  /// How far under (positive) or over (negative) the limit it ended.
  int get left => limit - spent;
}

/// Changes whenever any transaction changes, so finished periods can be
/// recounted.
final _transactionsRevisionProvider = StreamProvider<int>((ref) {
  return ref
      .watch(transactionRepositoryProvider)
      .watchSpentInRange(DateRange(DateTime(2000), DateTime(2100, 12, 31)));
});

/// Finished periods of every budget, [perBudget] of each at most.
final pastBudgetsProvider = FutureProvider.autoDispose
    .family<List<PastBudget>, int>((ref, perBudget) async {
      final limits = await ref.watch(budgetLimitsProvider.future);
      final categories = await ref.watch(allCategoriesProvider.future);
      ref.watch(_transactionsRevisionProvider);
      final today = ref.watch(clockProvider);
      final startDay = ref.watch(monthStartDayProvider);
      final repo = ref.read(transactionRepositoryProvider);

      final byTarget = <int?, List<LimitEntry>>{};
      for (final row in limits) {
        byTarget.putIfAbsent(row.categoryId, () => []).add(row.entry);
      }
      final out = <PastBudget>[];
      for (final MapEntry(key: categoryId, value: entries)
          in byTarget.entries) {
        final category = categoryId == null
            ? null
            : categories.where((c) => c.id == categoryId).firstOrNull;
        for (final period in pastPeriods(
          entries,
          today,
          monthStartDay: startDay,
          limit: perBudget,
        )) {
          out.add(
            PastBudget(
              categoryId: categoryId,
              category: category,
              entry: period.entry,
              range: period.range,
              limit: period.limit,
              spent: await repo.spentInRange(
                period.range,
                categoryId: categoryId,
              ),
            ),
          );
        }
      }
      return out;
    });
