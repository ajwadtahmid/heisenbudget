import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/budget_repository.dart';
import '../../domain/budget.dart';
import '../../providers/budget_providers.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';

/// After a new expense of [amountCents] was saved: a short sentence when it
/// took a budget over its limit, such as "Food is now over budget."; null
/// when it did not (or nothing was over before either).
///
/// Only the moment of crossing says anything: a budget that was already over
/// is not repeated on every expense after it.
Future<String?> overBudgetMessage(
  WidgetRef ref, {
  required int categoryId,
  required DateTime date,
  required int amountCents,
}) async {
  final startDay = ref.read(monthStartDayProvider);
  final limits = await ref.read(budgetRepositoryProvider).getAll();
  final entries = [for (final row in limits) row.entry];
  final transactions = ref.read(transactionRepositoryProvider);

  /// Whether this expense is the one that crossed the limit of the budget
  /// that covers its date.
  Future<bool> crossed(int? category) async {
    final budget = resolveBudget(
      entries,
      category,
      date,
      monthStartDay: startDay,
    );
    if (budget == null) return false;
    final after = await transactions.spentInRange(
      budget.range,
      categoryId: category,
    );
    return after > budget.limit && after - amountCents <= budget.limit;
  }

  final messages = <String>[];
  if (await crossed(categoryId)) {
    final categories = ref.read(allCategoriesProvider).value ?? const [];
    final name = categories
        .where((c) => c.id == categoryId)
        .map((c) => c.name)
        .firstOrNull;
    messages.add('${name ?? 'This category'} is now over budget.');
  }
  if (await crossed(null)) messages.add('All spending is now over budget.');
  return messages.isEmpty ? null : messages.join(' ');
}
