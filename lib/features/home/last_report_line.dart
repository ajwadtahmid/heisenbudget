import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/lab_report_providers.dart';
import '../../providers/settings_providers.dart';
import '../trends/lab_report_screen.dart';

/// A quiet row on Home for the rest of the month once last month's report card
/// is gone: it still opens that report. Nothing when there is none.
class LastReportLine extends ConsumerWidget {
  const LastReportLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(lastReportProvider);
    if (month == null) return const SizedBox.shrink();
    final c = context.appColors;
    final theme = Theme.of(context);
    final copy = ref.watch(copyProvider);
    final name = DateFormat.MMMM().format(DateTime(month.year, month.month));
    final text = '$name ${copy.reportTitle.toLowerCase()}';

    return Semantics(
      button: true,
      label: '$text. Opens the report.',
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('home-last-report'),
          onTap: () => openLabReport(context, month),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(Icons.assignment_outlined, size: 20, color: c.dim),
                const SizedBox(width: Gap.m),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: c.dim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: c.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
