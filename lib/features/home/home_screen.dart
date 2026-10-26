import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/design/counting_text.dart';
import '../../core/design/leader_row.dart';
import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/category_spend.dart';
import '../../domain/summary.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/transaction_providers.dart';
import '../shared/add_key.dart';
import '../shared/empty_state.dart';
import '../shared/period_selector.dart';
import '../shared/transaction_tile.dart';
import '../transaction_form/transaction_form_screen.dart';
import '../shared/transaction_menu.dart';
import 'coming_up_tile.dart';
import 'quick_add_strip.dart';
import 'spectrum_chart.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final copy = ref.watch(copyProvider);
    final symbol = settings.currencySymbol;
    final balance = ref.watch(balanceProvider).value ?? 0;
    final summary = ref.watch(periodSummaryProvider).value ?? Summary.empty;
    final spends = ref.watch(spendByCategoryProvider).value ?? const [];
    final recent = ref.watch(recentTransactionsProvider).value ?? const [];
    final comingUp = ref.watch(comingUpProvider);
    final c = context.appColors;
    final theme = Theme.of(context);

    final purity = purityPermille(summary.receivedCents, summary.spentCents);

    return Scaffold(
      floatingActionButton: const AddKey(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            Text(
              appName.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 2.2),
            ),
            const SizedBox(height: Gap.l),
            // The readout. It counts to new values and shrinks, never
            // wraps, when the amount is huge.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountingText(
                textKey: const ValueKey('balance'),
                value: balance,
                format: (v) => formatMoney(v, symbol),
                style: monoText(
                  size: 44,
                  weight: FontWeight.w600,
                  letterSpacing: -1,
                  color: balance < 0 ? c.spent : c.text,
                ),
              ),
            ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                Text('BALANCE', style: theme.textTheme.labelMedium),
                if (purity != null) ...[
                  const SizedBox(width: Gap.m),
                  // Shrinks, never wraps or overflows, at very large text.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          copy.purity(purityText(purity)),
                          key: const ValueKey('purity'),
                          style: monoText(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: c.dim,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gap.l),
            PeriodSelector(
              period: ref.watch(selectedPeriodProvider),
              today: ref.watch(clockProvider),
              weekMode: settings.weekMode,
              weekStartDay: settings.weekStartDay,
              onChanged: ref.read(selectedPeriodProvider.notifier).select,
            ),
            const SizedBox(height: Gap.s),
            LeaderRow(
              key: const ValueKey('row-received'),
              label: 'RECEIVED',
              icon: Icons.arrow_downward,
              value: formatMoney(summary.receivedCents, symbol, showPlus: true),
              valueColor: c.received,
            ),
            LeaderRow(
              key: const ValueKey('row-spent'),
              label: 'SPENT',
              icon: Icons.arrow_upward,
              value: formatMoney(-summary.spentCents, symbol),
              valueColor: c.spent,
            ),
            LeaderRow(
              key: const ValueKey('row-net'),
              label: 'NET',
              icon: Icons.drag_handle,
              value: formatMoney(summary.netCents, symbol, showPlus: true),
              valueColor: summary.netCents < 0 ? c.spent : c.text,
            ),
            const SizedBox(height: Gap.xl),
            SectionLabel(copy.chartTitle),
            const SizedBox(height: Gap.m),
            SpectrumChart(
              bars: buildSpectrum(spends),
              symbol: symbol,
              emptyText: copy.emptyChart,
            ),
            if (comingUp.isNotEmpty) ...[
              const SizedBox(height: Gap.xl),
              const SectionLabel('Coming up'),
              for (final item in comingUp)
                ComingUpTile(
                  key: ValueKey('coming-up-${item.rule.id}'),
                  item: item,
                  currencySymbol: symbol,
                  today: ref.watch(clockProvider),
                ),
            ],
            const QuickAddStrip(),
            const SizedBox(height: Gap.xl),
            SectionLabel(
              'Recent',
              trailing: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                onPressed: () =>
                    ref.read(shellTabProvider.notifier).select(historyTab),
                child: const Text('See all'),
              ),
            ),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Gap.l),
                child: EmptyState(
                  icon: Icons.show_chart,
                  message: copy.emptyRecent,
                ),
              )
            else
              for (final item in recent)
                TransactionTile(
                  key: ValueKey('recent-${item.transaction.id}'),
                  item: item,
                  currencySymbol: symbol,
                  showDate: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () =>
                      showTransactionForm(context, editId: item.transaction.id),
                  onLongPress: () => showTransactionMenu(context, ref, item),
                ),
          ],
        ),
      ),
    );
  }
}
