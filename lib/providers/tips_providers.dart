import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_providers.dart';
import 'favorite_providers.dart';
import 'recurring_providers.dart';
import 'settings_providers.dart';
import 'transaction_providers.dart';

/// A feature that makes logging or planning faster, which the person has not
/// used yet.
enum QuickTip { favorites, repeating, budgets }

/// Transactions logged before the tips card may appear: by then the app is in
/// daily use and the shortcuts are worth knowing.
const quickTipsAfter = 10;

/// The tips to show on Home: the unused ones, once at least [quickTipsAfter]
/// transactions exist and the card was not dismissed. Empty while anything is
/// still loading, so the card never flashes in and out.
final quickTipsProvider = Provider<List<QuickTip>>((ref) {
  if (ref.watch(settingsProvider.select((s) => s.tipsDismissed))) {
    return const [];
  }
  final count = ref.watch(transactionCountProvider).value;
  final favorites = ref.watch(favoritesProvider).value;
  final rules = ref.watch(recurringRulesProvider).value;
  final budgets = ref.watch(budgetOverviewProvider).value;
  if (count == null || count < quickTipsAfter) return const [];
  if (favorites == null || rules == null || budgets == null) return const [];
  return [
    if (favorites.isEmpty) QuickTip.favorites,
    if (rules.isEmpty) QuickTip.repeating,
    if (!budgets.hasAny) QuickTip.budgets,
  ];
});
