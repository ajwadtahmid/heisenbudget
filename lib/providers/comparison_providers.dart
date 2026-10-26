import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/comparison.dart';
import '../domain/summary.dart';
import 'database_providers.dart';
import 'period_providers.dart';
import 'settings_providers.dart';

/// What Home compares the selected period with, or null when the period has
/// not started.
final comparisonProvider = Provider<Comparison?>((ref) {
  final settings = ref.watch(settingsProvider);
  return buildComparison(
    period: ref.watch(selectedPeriodProvider),
    range: ref.watch(periodRangeProvider),
    today: ref.watch(clockProvider),
    mode: settings.weekMode,
    weekStartDay: settings.weekStartDay,
  );
});

/// Totals for the current side of the comparison (up to today while the
/// period is in progress).
final comparisonCurrentProvider = StreamProvider<Summary>((ref) {
  final comparison = ref.watch(comparisonProvider);
  if (comparison == null) return Stream.value(Summary.empty);
  return ref
      .watch(transactionRepositoryProvider)
      .watchSummary(comparison.current);
});

/// Totals for the earlier side.
final comparisonPreviousProvider = StreamProvider<Summary>((ref) {
  final comparison = ref.watch(comparisonProvider);
  if (comparison == null) return Stream.value(Summary.empty);
  return ref
      .watch(transactionRepositoryProvider)
      .watchSummary(comparison.previous);
});

/// What the delta lines on Home show.
class ComparisonView {
  const ComparisonView({
    required this.comparison,
    required this.spent,
    required this.received,
  });

  final Comparison comparison;

  /// Null when there is nothing to say about it (zero both times).
  final Delta? spent;
  final Delta? received;
}

/// The deltas for Spent and Received, or null when there is nothing worth
/// comparing: the period has not started, or nothing at all happened in the
/// earlier window (the first month, say), where a comparison would only be
/// noise.
final comparisonViewProvider = Provider<ComparisonView?>((ref) {
  final comparison = ref.watch(comparisonProvider);
  final current = ref.watch(comparisonCurrentProvider).value;
  final previous = ref.watch(comparisonPreviousProvider).value;
  if (comparison == null || current == null || previous == null) return null;
  if (previous.receivedCents == 0 && previous.spentCents == 0) return null;
  return ComparisonView(
    comparison: comparison,
    spent: compareTotals(
      current: current.spentCents,
      previous: previous.spentCents,
    ),
    received: compareTotals(
      current: current.receivedCents,
      previous: previous.receivedCents,
    ),
  );
});
