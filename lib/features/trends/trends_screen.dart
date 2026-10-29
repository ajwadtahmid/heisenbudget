import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../domain/trends.dart';
import '../../providers/category_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/trends_providers.dart';
import '../shared/empty_state.dart';
import '../shared/fact_row.dart';
import 'trace_chart.dart';
import 'trend_window_chips.dart';

/// Opens the Trends page over the app, on one category when [categoryId] is
/// given (the spending chart's "See trend").
Future<void> openTrends(
  BuildContext context,
  WidgetRef ref, {
  int? categoryId,
}) {
  if (categoryId != null) {
    ref.read(trendCategoryProvider.notifier).set(categoryId);
  }
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const TrendsScreen()));
}

/// Months side by side: the share kept month by month, and one category over
/// time.
class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final window = ref.watch(trendWindowProvider);
    final totals = ref.watch(trendTotalsProvider(window));

    final Widget body;
    if (totals.hasError && !totals.isLoading) {
      body = EmptyState(
        key: const ValueKey('trends-page-error'),
        icon: Icons.error_outline,
        message: 'Could not load your trends.',
        actionLabel: 'Try again',
        onAction: () => reloadTrends(ref),
      );
    } else if (totals.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final months = totals.value!;
      final withData = months.where((m) => !m.isEmpty).length;
      String nameOf(MonthTotals m) =>
          formatMonth(DateTime(m.month.year, m.month.month));
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const TrendWindowChips(keyPrefix: 'trends-window'),
          if (withData > 0) ...[
            const SizedBox(height: Gap.xl),
            SectionLabel(copy.purityByMonth),
            const SizedBox(height: Gap.s),
            for (final m in months.reversed)
              FactRow(
                label: m.inProgress ? '${nameOf(m)} (so far)' : nameOf(m),
                value: m.purity == null
                    ? 'nothing received'
                    : purityText(m.purity!),
                valueIsPlain: m.purity == null,
              ),
          ],
          const SizedBox(height: Gap.xl),
          const SectionLabel('A category over time'),
          const SizedBox(height: Gap.m),
          _CategoryBlock(window: window, months: months, symbol: symbol),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: body,
    );
  }
}

/// The category chips and the chosen category's months.
class _CategoryBlock extends ConsumerWidget {
  const _CategoryBlock({
    required this.window,
    required this.months,
    required this.symbol,
  });

  final int window;
  final List<MonthTotals> months;
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final choices = ref.watch(trendCategoryChoicesProvider(window)).value;
    final all = ref.watch(allCategoriesProvider).value ?? const <CategoryRow>[];
    if (choices == null) return const SizedBox(height: Gap.l);

    // The top few, plus the one asked for if it is not among them.
    final shown = <({int id, String name, String icon})>[
      for (final h in choices) (id: h.categoryId, name: h.name, icon: h.icon),
    ];
    final wanted = ref.watch(trendCategoryProvider);
    if (wanted != null && shown.every((s) => s.id != wanted)) {
      final row = all.where((r) => r.id == wanted).firstOrNull;
      if (row != null) shown.add((id: row.id, name: row.name, icon: row.icon));
    }

    Widget series() {
      if (wanted == null) {
        return Text(
          'Pick a category to see what it spent month by month.',
          key: const ValueKey('trend-category-hint'),
          style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
        );
      }
      final spent = ref.watch(
        trendCategorySeriesProvider((categoryId: wanted, count: window)),
      );
      return spent.when(
        data: (values) => TraceChart(
          key: ValueKey('trend-category-chart-$wanted'),
          points: categoryPointsOf(months, values),
          symbol: symbol,
          emptyText: ref.read(copyProvider).emptyTrends,
        ),
        loading: () => const SizedBox(height: 152),
        error: (_, _) => Text(
          'Could not load this part.',
          style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            ChoiceChip(
              key: const ValueKey('trend-category-none'),
              showCheckmark: false,
              label: const Text('None'),
              selected: wanted == null,
              onSelected: (_) =>
                  ref.read(trendCategoryProvider.notifier).set(null),
            ),
            for (final s in shown)
              ChoiceChip(
                key: ValueKey('trend-category-${s.id}'),
                showCheckmark: false,
                avatar: Icon(categoryIconFor(s.icon).icon, size: 18),
                label: Text(s.name),
                selected: wanted == s.id,
                onSelected: (_) =>
                    ref.read(trendCategoryProvider.notifier).set(s.id),
              ),
          ],
        ),
        const SizedBox(height: Gap.m),
        series(),
      ],
    );
  }
}
