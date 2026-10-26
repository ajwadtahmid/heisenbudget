import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/budget.dart';
import '../domain/category_spend.dart';
import '../domain/date_range.dart';
import '../domain/summary.dart';
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

/// The budget month that today falls in.
final currentBudgetMonthProvider = Provider<BudgetMonth>(
  (ref) => BudgetMonth.containing(
    ref.watch(clockProvider),
    ref.watch(monthStartDayProvider),
  ),
);

/// How far from the current budget month the Budgets screen is looking:
/// 0 = this month, -1 = last month, 1 = next month.
final budgetMonthOffsetProvider = NotifierProvider<BudgetMonthOffset, int>(
  BudgetMonthOffset.new,
);

class BudgetMonthOffset extends Notifier<int> {
  /// How far ahead may be looked at.
  static const maxAhead = 12;

  /// How far back (about four years).
  static const maxBack = -48;

  @override
  int build() => 0;

  void set(int offset) => state = offset.clamp(maxBack, maxAhead);

  void step(int delta) => set(state + delta);
}

/// The month the Budgets screen shows.
final selectedBudgetMonthProvider = Provider<BudgetMonth>(
  (ref) => ref
      .watch(currentBudgetMonthProvider)
      .shift(ref.watch(budgetMonthOffsetProvider)),
);

/// Expense totals per category inside [range] (all of them, not just the top
/// few).
final _budgetSpendProvider =
    StreamProvider.family<List<CategorySpend>, DateRange>(
      (ref, range) =>
          ref.watch(transactionRepositoryProvider).watchSpendByCategory(range),
    );

/// Total spending inside [range].
final _budgetTotalProvider = StreamProvider.family<Summary, DateRange>(
  (ref, range) => ref.watch(transactionRepositoryProvider).watchSummary(range),
);

/// One budget on screen: a category's, or all spending's (no category).
class BudgetLine {
  const BudgetLine({
    required this.categoryId,
    required this.category,
    required this.status,
  });

  final int? categoryId;
  final CategoryRow? category;
  final BudgetStatus status;

  bool get isOverall => categoryId == null;
}

/// Everything the Budgets screen and Home need for one budget month.
class BudgetOverview {
  const BudgetOverview({
    required this.month,
    required this.range,
    required this.overall,
    required this.lines,
    required this.withoutLimit,
    required this.categoryLimitTotal,
  });

  final BudgetMonth month;
  final DateRange range;

  /// The limit on all spending, if there is one.
  final BudgetLine? overall;

  /// Categories that have a limit, the ones in trouble first.
  final List<BudgetLine> lines;

  /// Expense categories that have no limit this month.
  final List<CategoryRow> withoutLimit;

  /// The category limits added up.
  final int categoryLimitTotal;

  bool get hasAny => overall != null || lines.isNotEmpty;

  /// The category limits together are more than the overall limit.
  bool get categoriesExceedOverall =>
      overall != null && categoryLimitTotal > overall!.status.limit;

  Iterable<BudgetLine> get all => [?overall, ...lines];

  int get overCount =>
      all.where((l) => l.status.level == BudgetLevel.over).length;

  int get almostCount =>
      all.where((l) => l.status.level == BudgetLevel.almost).length;
}

/// The budgets for [month]. Null until what it needs has loaded.
final budgetOverviewProvider = Provider.family<BudgetOverview?, BudgetMonth>((
  ref,
  month,
) {
  final startDay = ref.watch(monthStartDayProvider);
  final range = month.range(startDay);
  final limits = ref.watch(budgetLimitsProvider).value;
  final spend = ref.watch(_budgetSpendProvider(range)).value;
  final total = ref.watch(_budgetTotalProvider(range)).value;
  final categories = ref.watch(allCategoriesProvider).value;
  final rules = ref.watch(recurringRulesProvider).value ?? const [];
  final today = ref.watch(clockProvider);
  if (limits == null || spend == null || total == null || categories == null) {
    return null;
  }

  final entries = [for (final row in limits) row.entry];
  final spentBy = {for (final s in spend) s.categoryId: s.cents};
  final planned = plannedByCategory(
    [
      for (final rule in rules)
        if (rule.isActive && rule.type == TransactionType.expense)
          PlannedRule(
            categoryId: rule.categoryId,
            amountCents: rule.amountCents,
            recurrence: rule.recurrence,
            nextIndex: rule.nextIndex,
          ),
    ],
    range,
    today,
  );

  BudgetStatus status(int limit, int spent, int plannedCents) =>
      buildBudgetStatus(
        limit: limit,
        spent: spent,
        planned: plannedCents,
        range: range,
        today: today,
      );

  final expense = categories
      .where((c) => c.type == TransactionType.expense)
      .toList();
  final lines = <BudgetLine>[];
  final withoutLimit = <CategoryRow>[];
  var categoryTotal = 0;
  for (final category in expense) {
    final limit = resolveLimit(entries, category.id, month);
    if (limit == null) {
      if (!category.isArchived) withoutLimit.add(category);
      continue;
    }
    categoryTotal += limit;
    lines.add(
      BudgetLine(
        categoryId: category.id,
        category: category,
        status: status(
          limit,
          spentBy[category.id] ?? 0,
          planned[category.id] ?? 0,
        ),
      ),
    );
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

  final overallLimit = resolveLimit(entries, null, month);
  final plannedTotal = planned.values.fold<int>(0, (a, b) => a + b);
  return BudgetOverview(
    month: month,
    range: range,
    overall: overallLimit == null
        ? null
        : BudgetLine(
            categoryId: null,
            category: null,
            status: status(overallLimit, total.spentCents, plannedTotal),
          ),
    lines: lines,
    withoutLimit: withoutLimit,
    categoryLimitTotal: categoryTotal,
  );
});

/// The budgets for the month the Budgets screen is showing.
final selectedBudgetOverviewProvider = Provider<BudgetOverview?>(
  (ref) =>
      ref.watch(budgetOverviewProvider(ref.watch(selectedBudgetMonthProvider))),
);

/// The budgets for this month, for Home's one line.
final currentBudgetOverviewProvider = Provider<BudgetOverview?>(
  (ref) =>
      ref.watch(budgetOverviewProvider(ref.watch(currentBudgetMonthProvider))),
);

/// What Home says about budgets.
class BudgetSummary {
  const BudgetSummary({required this.over, required this.almost});

  final int over;
  final int almost;
}

/// Null when there is no budget this month (Home then shows nothing).
final budgetSummaryProvider = Provider<BudgetSummary?>((ref) {
  final overview = ref.watch(currentBudgetOverviewProvider);
  if (overview == null || !overview.hasAny) return null;
  return BudgetSummary(over: overview.overCount, almost: overview.almostCount);
});

/// A suggested limit: the average of what was spent in the three budget
/// months before [month], for one category or (null) all spending. Null when
/// nothing was spent in them.
Future<int?> suggestedLimit({
  required TransactionRepository repo,
  required int startDay,
  required BudgetMonth month,
  int? categoryId,
}) async {
  final spends = <int>[];
  for (var back = 1; back <= 3; back++) {
    spends.add(
      await repo.spentInRange(
        month.shift(-back).range(startDay),
        categoryId: categoryId,
      ),
    );
  }
  return suggestLimit(spends);
}
