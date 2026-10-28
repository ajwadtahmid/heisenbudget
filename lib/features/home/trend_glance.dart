import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/trends.dart';
import '../../providers/settings_providers.dart';
import '../../providers/trends_providers.dart';
import '../trends/trends_screen.dart';
import 'home_glance.dart';

/// The last six months of spending as small peaks, and one sentence on how
/// the last finished month compares. Nothing at all until something has been
/// logged. "See all" opens Trends.
class TrendGlance extends ConsumerWidget {
  const TrendGlance({super.key});

  static const months = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final totals = ref.watch(trendTotalsProvider(months));
    final c = context.appColors;
    final theme = Theme.of(context);

    Widget glance(Widget child) => Padding(
      padding: const EdgeInsets.only(top: Gap.xl),
      child: HomeGlance(
        label: '${copy.trendsTitle} · last $months months',
        onSeeAll: () => openTrends(context),
        child: child,
      ),
    );

    if (totals.hasError && !totals.isLoading) {
      return glance(
        Text(
          'Could not load this part.',
          key: const ValueKey('trend-glance-error'),
          style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
        ),
      );
    }
    final data = totals.value;
    if (data == null || data.every((m) => m.isEmpty)) {
      return const SizedBox.shrink();
    }

    final comparison = compareLastMonth(data);
    return glance(
      InkWell(
        key: const ValueKey('trend-glance'),
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: () => openTrends(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MiniPeaks(totals: data, symbol: symbol),
            const SizedBox(height: Gap.s),
            Text(
              _sentence(comparison, symbol),
              key: const ValueKey('trend-glance-text'),
              style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
            ),
          ],
        ),
      ),
    );
  }

  static String _sentence(SpendComparison? comparison, String symbol) {
    if (comparison == null) {
      return 'A second month of history unlocks the comparison.';
    }
    final month = DateFormat.MMMM().format(
      DateTime(comparison.month.month.year, comparison.month.month.month),
    );
    final spent = formatMoney(comparison.month.spentCents, symbol);
    final average = '${comparison.monthsAveraged}-month average';
    final p = comparison.percent;
    final how = p == 0
        ? 'in line with your $average'
        : '${p.abs()}% ${p < 0 ? 'under' : 'over'} your $average';
    return '$month: spent $spent, $how.';
  }
}

/// Six small peaks of what was spent each month, the month still going drawn
/// lighter, the month name under each.
class _MiniPeaks extends StatelessWidget {
  const _MiniPeaks({required this.totals, required this.symbol});

  final List<MonthTotals> totals;
  final String symbol;

  static const _room = 48.0;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final biggest = totals.fold<int>(
      0,
      (m, t) => t.spentCents > m ? t.spentCents : m,
    );
    final spoken = [
      for (final t in totals)
        '${DateFormat.MMMM().format(DateTime(t.month.year, t.month.month))} '
            '${formatMoney(t.spentCents, symbol)}'
            '${t.inProgress ? ' so far' : ''}',
    ].join(', ');

    return Semantics(
      container: true,
      label: 'Spending by month: $spoken',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final t in totals)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: _room,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 16,
                          height: t.spentCents == 0 || biggest == 0
                              ? 2
                              : (_room * t.spentCents / biggest).clamp(
                                  3.0,
                                  _room,
                                ),
                          decoration: BoxDecoration(
                            color: c.spentFill.withValues(
                              alpha: t.inProgress ? 0.55 : 1,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        DateFormat.MMM().format(
                          DateTime(t.month.year, t.month.month),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: c.dim,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
