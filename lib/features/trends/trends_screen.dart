import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/category_icons.dart';
import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../domain/iso_date.dart';
import '../../domain/trends.dart';
import '../../providers/category_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/trends_providers.dart';
import '../shared/category_tile.dart';
import '../shared/empty_state.dart';
import 'trace_chart.dart';

/// Opens the Trends page over the app, on one category when [categoryId] is
/// given.
Future<void> openTrends(BuildContext context, {int? categoryId}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TrendsScreen(initialCategoryId: categoryId),
    ),
  );
}

/// Months side by side: money in and out, one category over time, what moved
/// most, and how this month has run. [initialCategoryId] opens it on one
/// category (from the spending chart's "See trend").
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key, this.initialCategoryId});

  final int? initialCategoryId;

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  bool _asList = false;
  late int? _categoryId = widget.initialCategoryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final window = ref.watch(trendWindowProvider);
    final totals = ref.watch(trendTotalsProvider(window));

    Widget body;
    if (totals.hasError && !totals.isLoading) {
      body = EmptyState(
        key: const ValueKey('trends-error'),
        icon: Icons.error_outline,
        message: 'Could not load your trends.',
        actionLabel: 'Try again',
        onAction: () => reloadTrends(ref),
      );
    } else if (totals.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final months = totals.value!;
      final points = tracePointsOf(months);
      final withData = months.where((m) => !m.isEmpty).length;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Wrap(
            spacing: Gap.m,
            children: [
              for (final n in trendWindows)
                ChoiceChip(
                  key: ValueKey('trend-window-$n'),
                  showCheckmark: false,
                  label: Text('$n months'),
                  selected: window == n,
                  onSelected: (_) =>
                      ref.read(trendWindowProvider.notifier).set(n),
                ),
            ],
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Money in and out'),
          const SizedBox(height: Gap.m),
          if (_asList)
            TraceList(points: points, symbol: symbol)
          else
            TraceChart(
              points: points,
              symbol: symbol,
              emptyText: copy.emptyTrends,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('trace-list-toggle'),
              onPressed: () => setState(() => _asList = !_asList),
              icon: Icon(_asList ? Icons.bar_chart : Icons.view_list_outlined),
              label: Text(_asList ? 'Show as a chart' : 'Show as a list'),
            ),
          ),
          if (withData == 1)
            Text(
              'Needs a second month of history to compare months.',
              key: const ValueKey('trends-thin'),
              style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
            ),
          if (withData > 0) ...[
            const SizedBox(height: Gap.xl),
            SectionLabel(copy.purityByMonth),
            const SizedBox(height: Gap.s),
            for (final m in months.reversed)
              _FactRow(
                label: m.inProgress
                    ? '${_monthName(m)} (so far)'
                    : _monthName(m),
                value: m.purity == null
                    ? 'nothing received'
                    : purityText(m.purity!),
                valueIsPlain: m.purity == null,
              ),
          ],
          const SizedBox(height: Gap.xl),
          const SectionLabel('A category over time'),
          const SizedBox(height: Gap.m),
          _categoryBlock(window, months, symbol),
          ..._moversBlock(symbol),
          ..._recordsBlock(symbol),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(copy.trendsTitle)),
      body: body,
    );
  }

  static String _monthName(MonthTotals m) =>
      DateFormat.yMMMM().format(DateTime(m.month.year, m.month.month));

  Widget _categoryBlock(int window, List<MonthTotals> months, String symbol) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final choices = ref.watch(trendCategoryChoicesProvider(window)).value;
    final all = ref.watch(allCategoriesProvider).value ?? const <CategoryRow>[];
    if (choices == null) return const SizedBox(height: Gap.l);

    // The top few, plus the one asked for if it is not among them.
    final shown = <({int id, String name, String icon})>[
      for (final h in choices) (id: h.categoryId, name: h.name, icon: h.icon),
    ];
    final wanted = _categoryId;
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
              onSelected: (_) => setState(() => _categoryId = null),
            ),
            for (final s in shown)
              ChoiceChip(
                key: ValueKey('trend-category-${s.id}'),
                showCheckmark: false,
                avatar: Icon(categoryIconFor(s.icon).icon, size: 18),
                label: Text(s.name),
                selected: wanted == s.id,
                onSelected: (_) => setState(() => _categoryId = s.id),
              ),
          ],
        ),
        const SizedBox(height: Gap.m),
        series(),
      ],
    );
  }

  List<Widget> _moversBlock(String symbol) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final movers = ref.watch(trendMoversProvider).value;
    if (movers == null || (movers.up.isEmpty && movers.down.isEmpty)) {
      return const [];
    }
    Widget row(CategoryMove m, {required bool up}) => MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: [
            CategoryTile(iconKey: m.icon, size: 32),
            const SizedBox(width: Gap.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: theme.textTheme.bodyMedium),
                  Text(
                    '${formatMoney(m.currentCents, symbol)} against '
                    '${formatMoney(m.averageCents, symbol)} usually',
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.s),
            Icon(
              up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: up ? c.spent : c.dim,
            ),
            Text(
              formatMoney(m.deltaCents, symbol, showPlus: true),
              style: monoText(size: 14, color: up ? c.spent : c.dim),
            ),
          ],
        ),
      ),
    );

    final month = DateFormat.MMMM().format(
      DateTime(movers.month.year, movers.month.month),
    );
    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('What moved'),
      const SizedBox(height: Gap.xs),
      Text(
        '$month against the ${movers.monthsAveraged} '
        'month${movers.monthsAveraged == 1 ? '' : 's'} before it.',
        key: const ValueKey('movers-note'),
        style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
      ),
      const SizedBox(height: Gap.s),
      for (final m in movers.up) row(m, up: true),
      for (final m in movers.down) row(m, up: false),
    ];
  }

  List<Widget> _recordsBlock(String symbol) {
    final records = ref.watch(trendRecordsProvider).value;
    if (records == null) return const [];
    final r = records.rhythm;
    final biggest = records.biggest;
    String days(int n) => '$n day${n == 1 ? '' : 's'}';
    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('This month so far'),
      const SizedBox(height: Gap.s),
      if (biggest != null)
        _FactRow(
          label: 'Biggest expense',
          subtitle:
              '${biggest.transaction.title ?? biggest.category.name} · '
              '${formatDate(fromIsoDate(biggest.transaction.date))}',
          value: formatMoney(-biggest.transaction.amountCents, symbol),
        ),
      if (r.busiestDay != null)
        _FactRow(
          label: 'Busiest day',
          subtitle: formatDate(r.busiestDay!),
          value: formatMoney(-r.busiestDayCents, symbol),
        ),
      _FactRow(
        label: 'Average a day',
        value: formatMoney(-r.averagePerDayCents, symbol),
      ),
      _FactRow(
        label: 'Days with no spending',
        subtitle: 'of ${days(r.days)} so far',
        value: '${r.noSpendDays}',
      ),
      _FactRow(
        label: 'Longest run with none',
        value: days(r.longestNoSpendStreak),
        valueIsPlain: true,
      ),
    ];
  }
}

/// A label (and a dim line under it) at the left, a value at the right. Both
/// shrink and wrap together at large text instead of overflowing.
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.subtitle,
    this.valueIsPlain = false,
  });

  final String label;
  final String value;
  final String? subtitle;

  /// Words rather than an amount: not set in the mono figures.
  final bool valueIsPlain;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.m),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: valueIsPlain
                    ? theme.textTheme.bodyMedium?.copyWith(color: c.dim)
                    : monoText(size: 15, color: c.text),
              ),
            ),
          ),
        ],
      ),
    );
    return MergeSemantics(child: row);
  }
}
