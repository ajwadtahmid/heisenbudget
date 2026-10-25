import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
import '../domain/category_spend.dart';
import '../domain/summary.dart';
import 'database_providers.dart';
import 'period_providers.dart';
import 'settings_providers.dart';

/// Received / Spent / Net for the period selected on Home.
final periodSummaryProvider = StreamProvider<Summary>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.watchSummary(ref.watch(periodRangeProvider));
});

/// Current balance in cents: opening balance + income - expenses, counting
/// only transactions dated today or earlier.
final balanceProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  final today = ref.watch(clockProvider);
  final opening = ref.watch(
    settingsProvider.select((s) => s.openingBalanceCents),
  );
  return repo.watchTotalsUpTo(today).map((totals) => opening + totals.netCents);
});

/// Spending per category for the selected period (biggest first).
final spendByCategoryProvider = StreamProvider<List<CategorySpend>>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.watchSpendByCategory(ref.watch(periodRangeProvider));
});

/// One transaction, loaded once for the edit form.
final transactionByIdProvider = FutureProvider.autoDispose
    .family<TransactionWithCategory?, int>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getById(id);
    });

/// Categories that have transactions (so History can offer archived ones).
final usedCategoryIdsProvider = StreamProvider<Set<int>>((ref) {
  return ref.watch(transactionRepositoryProvider).watchUsedCategoryIds();
});

/// The last 3 transactions inside the selected period.
final recentTransactionsProvider =
    StreamProvider<List<TransactionWithCategory>>((ref) {
      final repo = ref.watch(transactionRepositoryProvider);
      return repo.watchByRange(ref.watch(periodRangeProvider), limit: 3);
    });

/// Whether to show the first-run welcome. People who already have data (an
/// install from before the tour existed) never see it.
final needsWelcomeProvider = FutureProvider<bool>((ref) async {
  // Read, not watched: this provider itself sets the flag below, and the app
  // root already switches to the app as soon as the flag is true.
  final done = ref.read(settingsProvider).onboardingDone;
  if (done) return false;
  final hasData = await ref.watch(transactionRepositoryProvider).hasAny();
  if (hasData) {
    await ref.read(settingsProvider.notifier).setOnboardingDone(true);
    return false;
  }
  return true;
});
