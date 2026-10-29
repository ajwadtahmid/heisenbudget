import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../providers/lab_report_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/empty_state.dart';
import '../shared/fact_row.dart';
import 'lab_report_screen.dart';

/// Opens the list of month-end reports over the app.
Future<void> openReports(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
}

/// The finished months that have a report, newest first.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final months = ref.watch(reportMonthsProvider);

    final Widget body;
    if (months.hasError && !months.isLoading) {
      body = EmptyState(
        key: const ValueKey('reports-error'),
        icon: Icons.error_outline,
        message: 'Could not load your reports.',
        actionLabel: 'Try again',
        onAction: () => reloadReports(ref),
      );
    } else if (months.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (months.value!.isEmpty) {
      body = const EmptyState(
        key: ValueKey('reports-empty'),
        icon: Icons.description_outlined,
        message: 'No finished months yet. A report appears once a month ends.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          for (final m in months.value!)
            FactRow(
              key: ValueKey('report-month-${m.month.key}'),
              label: formatMonth(DateTime(m.month.year, m.month.month)),
              subtitle: m.purity == null
                  ? 'Nothing received'
                  : copy.purity(purityText(m.purity!)),
              value: formatMoney(m.netCents, symbol, showPlus: true),
              onTap: () => openLabReport(context, m.month),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(copy.reportsLabel)),
      body: body,
    );
  }
}
