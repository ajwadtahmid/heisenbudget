import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/settings_providers.dart';
import '../../providers/trends_providers.dart';
import '../shared/empty_state.dart';
import 'trace_chart.dart';
import 'trend_window_chips.dart';

/// Opens the Money in and out page over the app.
Future<void> openMoney(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const MoneyScreen()));
}

/// The last 3, 6 or 12 months of money in and out as peaks, with the same
/// months as a list.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  bool _asList = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final window = ref.watch(trendWindowProvider);
    final totals = ref.watch(trendTotalsProvider(window));

    final Widget body;
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
          const TrendWindowChips(keyPrefix: 'trend-window'),
          const SizedBox(height: Gap.l),
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
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Money in and out')),
      body: body,
    );
  }
}
