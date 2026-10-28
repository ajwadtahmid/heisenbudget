import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/lab_report_providers.dart';
import '../../providers/settings_providers.dart';
import '../trends/lab_report_screen.dart';

/// A quiet card on Home in the first days of a new budget month: last month's
/// report is ready. It goes once the report is opened or dismissed. Nothing at
/// all when there is no report to announce.
class ReportNoticeCard extends ConsumerWidget {
  const ReportNoticeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportNoticeProvider);
    if (month == null) return const SizedBox.shrink();
    final c = context.appColors;
    final theme = Theme.of(context);
    final copy = ref.watch(copyProvider);
    final title = copy.reportReady(
      DateFormat.MMMM().format(DateTime(month.year, month.month)),
    );
    const body =
        'What came in and went out, how your budgets did, and what to do next.';

    return Semantics(
      container: true,
      label: '$title. $body',
      child: Container(
        key: const ValueKey('report-notice'),
        margin: const EdgeInsets.only(bottom: Gap.l),
        padding: const EdgeInsets.all(Gap.l),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(Radii.panel),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 20, color: c.dim),
                const SizedBox(width: Gap.m),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.s),
            // Wraps to more lines at large text instead of overflowing.
            OverflowBar(
              alignment: MainAxisAlignment.start,
              spacing: Gap.s,
              overflowSpacing: Gap.xs,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('report-open'),
                  onPressed: () => openLabReport(context, month),
                  child: const Text('Open report'),
                ),
                TextButton(
                  key: const ValueKey('report-dismiss'),
                  onPressed: () => markReportSeen(ref, month),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
