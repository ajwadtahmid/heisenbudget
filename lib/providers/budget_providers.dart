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

/// The weekday weeks start on (1 = Monday to 7 = Sunday). A new budget of
/// whole weeks (weekly, every 2 weeks...) starts on it, whatever the Home
/// period menu is set to.
final weekStartDayProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider.select((s) => s.weekStartDay)),
);

/// The things to total spending for (the range and category of each budget in
/// force), as one family key so every budget on screen shares one stream.
class _SpendKeys {
  const _SpendKeys(this.keys);

  final List<SpendKey> keys;

  @override
  bool operator ==(Object other) =>
      other is _SpendKeys &&
      other.keys.length == keys.length &&
      [for (var i = 0; i < keys.length; i++) keys[i] == other.keys[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hashAll(keys);
}

/// What was spent for each of the keys, in the same order, from one query that
/// updates as transactions change (not one stream per budget).
final _spentManyProvider = StreamProvider.family<List<int>, _SpendKeys>(
  (ref, key) =>
      ref.watch(transactionRepositoryProvider).watchSpentForKeys(key.keys),
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

/// The budgets in force today, with how each is doing. Loading until the
/// spending for each has loaded; an error if any of it cannot be read, so a
/// failed read is never shown as an endless wait.
final budgetOverviewProvider = Provider<AsyncValue<BudgetOverview>>((ref) {
  final limitsAsync = ref.watch(budgetLimitsProvider);
  final categoriesAsync = ref.watch(allCategoriesProvider);
  final rules = ref.watch(recurringRulesProvider).value ?? const [];
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  // Loading comes first: a reload keeps the old error until it finishes.
  for (final input in [limitsAsync, categoriesAsync]) {
    if (input.isLoading) return const AsyncLoading();
    if (input.hasError) return AsyncError(input.error!, input.stackTrace!);
  }
  final limits = limitsAsync.value;
  final categories = categoriesAsync.value;
  if (limits == null || categories == null) return const AsyncLoading();

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

  // Which budgets are in force today, and so what has to be totalled.
  ResolvedBudget? resolve(int? categoryId) =>
      resolveBudget(entries, categoryId, today, monthStartDay: startDay);
  final overallBudget = resolve(null);
  final expenseCategories = [
    for (final category in categories)
      if (category.type == TransactionType.expense) category,
  ];
  final byCategory = [for (final c in expenseCategories) resolve(c.id)];
  final keys = <SpendKey>[
    if (overallBudget != null) (overallBudget.range, null),
    for (var i = 0; i < expenseCategories.length; i++)
      if (byCategory[i] != null)
        (byCategory[i]!.range, expenseCategories[i].id),
  ];

  // One stream for all of them. Loading or a failure ends the whole overview.
  var spent = const <int>[];
  if (keys.isNotEmpty) {
    final spentAsync = ref.watch(_spentManyProvider(_SpendKeys(keys)));
    if (spentAsync.isLoading) return const AsyncLoading();
    if (spentAsync.hasError) {
      return AsyncError(spentAsync.error!, spentAsync.stackTrace!);
    }
    final value = spentAsync.value;
    if (value == null) return const AsyncLoading();
    spent = value;
  }

  var next = 0;
  BudgetLine? line(
    int? categoryId,
    CategoryRow? category,
    ResolvedBudget? resolved,
  ) {
    if (resolved == null) return null;
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
        spent: spent[next++],
        planned: plannedCents,
        range: resolved.range,
        today: today,
      ),
    );
  }

  final overall = line(null, null, overallBudget);
  final lines = <BudgetLine>[];
  final withoutLimit = <CategoryRow>[];
  for (var i = 0; i < expenseCategories.length; i++) {
    final category = expenseCategories[i];
    final l = line(category.id, category, byCategory[i]);
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
  return AsyncData(
    BudgetOverview(
      overall: overall,
      lines: lines,
      withoutLimit: withoutLimit,
      sameUnitCategoryTotal: sameUnit,
    ),
  );
});

/// For each budget on the Budgets screen (by category id; null is all
/// spending): that it usually runs over, when it does. Looks at up to six
/// finished periods of the budget's current length (ones a later change cut
/// short do not count). Empty until the spending has loaded, and for a budget
/// with too little history to say.
final budgetOverrunHintsProvider = Provider<Map<int?, OverrunHint>>((ref) {
  final overview = ref.watch(budgetOverviewProvider).value;
  final limits = ref.watch(budgetLimitsProvider).value;
  if (overview == null || limits == null) return const {};
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  final entries = [for (final row in limits) row.entry];

  final periods = <int?, List<PastPeriod>>{};
  final keys = <SpendKey>[];
  for (final line in overview.all) {
    final past = pastPeriods(
      entries.where((e) => e.categoryId == line.categoryId),
      today,
      monthStartDay: startDay,
      limit: 24,
    ).where((p) => !p.endedEarly && p.entry.unit == line.unit).take(6).toList();
    if (past.length < 3) continue;
    periods[line.categoryId] = past;
    for (final p in past) {
      keys.add((p.range, line.categoryId));
    }
  }
  if (keys.isEmpty) return const {};
  final spent = ref.watch(_spentManyProvider(_SpendKeys(keys))).value;
  if (spent == null) return const {};

  final hints = <int?, OverrunHint>{};
  var next = 0;
  for (final entry in periods.entries) {
    final results = [
      for (final p in entry.value) (limit: p.limit, spent: spent[next++]),
    ];
    final hint = overrunHint(results);
    if (hint != null) hints[entry.key] = hint;
  }
  return hints;
});

/// Reads everything the overview needs again (the Budgets screen's "Try
/// again").
void reloadBudgets(WidgetRef ref) {
  ref.invalidate(budgetLimitsProvider);
  ref.invalidate(allCategoriesProvider);
  ref.invalidate(_spentManyProvider);
}

/// What Home says about budgets.
class BudgetSummary {
  const BudgetSummary({required this.over, required this.almost});

  final int over;
  final int almost;
}

/// Null when no budget is in force (Home then shows nothing).
final budgetSummaryProvider = Provider<BudgetSummary?>((ref) {
  final overview = ref.watch(budgetOverviewProvider).value;
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
    this.endedEarly = false,
  });

  final int? categoryId;
  final CategoryRow? category;
  final LimitEntry entry;
  final DateRange range;
  final int limit;
  final int spent;

  /// A later change cut this period short ([range] ends before it would have).
  final bool endedEarly;

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
