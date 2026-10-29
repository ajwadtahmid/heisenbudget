import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/iso_date.dart';
import '../../providers/settings_providers.dart';
import '../../providers/trends_providers.dart';
import '../shared/empty_state.dart';
import '../shared/fact_row.dart';
import 'mover_row.dart';

/// Opens the This month page over the app.
Future<void> openThisMonth(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ThisMonthScreen()));
}

/// How this month has run so far, and what moved most against the months
/// before it.
class ThisMonthScreen extends ConsumerWidget {
  const ThisMonthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final records = ref.watch(trendRecordsProvider);

    final Widget body;
    if (records.hasError && !records.isLoading) {
      body = EmptyState(
        key: const ValueKey('this-month-error'),
        icon: Icons.error_outline,
        message: 'Could not load this month.',
        actionLabel: 'Try again',
        onAction: () => reloadTrends(ref),
      );
    } else if (records.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          ..._recordsBlock(ref, symbol),
          ..._moversBlock(context, ref, symbol),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('This month')),
      body: body,
    );
  }

  List<Widget> _moversBlock(
    BuildContext context,
    WidgetRef ref,
    String symbol,
  ) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final movers = ref.watch(trendMoversProvider).value;
    if (movers == null || (movers.up.isEmpty && movers.down.isEmpty)) {
      return const [];
    }
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
      for (final m in movers.up) MoverRow(move: m, up: true, symbol: symbol),
      for (final m in movers.down) MoverRow(move: m, up: false, symbol: symbol),
    ];
  }

  List<Widget> _recordsBlock(WidgetRef ref, String symbol) {
    final records = ref.watch(trendRecordsProvider).value;
    if (records == null) return const [];
    final r = records.rhythm;
    final biggest = records.biggest;
    String days(int n) => '$n day${n == 1 ? '' : 's'}';
    return [
      const SectionLabel('This month so far'),
      const SizedBox(height: Gap.s),
      if (biggest != null)
        FactRow(
          label: 'Biggest expense',
          subtitle:
              '${biggest.transaction.title ?? biggest.category.name} · '
              '${formatDate(fromIsoDate(biggest.transaction.date))}',
          value: formatMoney(-biggest.transaction.amountCents, symbol),
        ),
      if (r.busiestDay != null)
        FactRow(
          label: 'Busiest day',
          subtitle: formatDate(r.busiestDay!),
          value: formatMoney(-r.busiestDayCents, symbol),
        ),
      FactRow(
        label: 'Average a day',
        value: formatMoney(-r.averagePerDayCents, symbol),
      ),
      FactRow(
        label: 'Days with no spending',
        subtitle: 'of ${days(r.days)} so far',
        value: '${r.noSpendDays}',
      ),
      FactRow(
        label: 'Longest run with none',
        value: days(r.longestNoSpendStreak),
        valueIsPlain: true,
      ),
    ];
  }
}
