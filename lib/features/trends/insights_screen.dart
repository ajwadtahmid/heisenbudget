import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/lab_report_providers.dart';
import '../../providers/settings_providers.dart';
import '../goals/goals_row.dart';
import '../goals/goals_screen.dart';
import '../home/report_notice_card.dart';
import '../shared/insight_row.dart';
import 'money_screen.dart';
import 'reports_screen.dart';
import 'this_month_screen.dart';
import 'trends_screen.dart';

/// The Insights tab: the month-end report when one is due, then a row to each
/// page (money in and out, goals, trends, this month, reports).
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = ref.watch(copyProvider);
    final reports = ref.watch(reportMonthsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            key: const ValueKey('insights-goals-button'),
            tooltip: 'Goals',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => openGoals(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const ReportNoticeCard(),
          InsightRow(
            key: const ValueKey('insights-money'),
            icon: Icons.stacked_bar_chart,
            title: 'Money in and out',
            subtitle: 'The last 3, 6 or 12 months side by side',
            onTap: () => openMoney(context),
          ),
          const GoalsRow(),
          InsightRow(
            key: const ValueKey('insights-trends'),
            icon: Icons.show_chart,
            title: 'Trends',
            subtitle: '${copy.purityByMonth}, and one category over time',
            onTap: () => openTrends(context, ref),
          ),
          InsightRow(
            key: const ValueKey('insights-month'),
            icon: Icons.calendar_month_outlined,
            title: 'This month',
            subtitle: 'Records so far, and what moved',
            onTap: () => openThisMonth(context),
          ),
          InsightRow(
            key: const ValueKey('insights-reports'),
            icon: Icons.description_outlined,
            title: copy.reportsLabel,
            subtitle: reports == null || reports.isEmpty
                ? 'None yet'
                : '${reports.length} finished '
                      'month${reports.length == 1 ? '' : 's'}',
            onTap: () => openReports(context),
          ),
        ],
      ),
    );
  }
}
