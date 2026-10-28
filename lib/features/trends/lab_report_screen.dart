import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../domain/iso_date.dart';
import '../../domain/lab_report.dart';
import '../../domain/trends.dart';
import '../../providers/budget_providers.dart';
import '../../providers/lab_report_providers.dart';
import '../../providers/settings_providers.dart';
import '../budgets/budget_editor.dart';
import '../settings/backup_actions.dart';
import '../shared/empty_state.dart';
import '../shared/fact_row.dart';
import '../transaction_form/transaction_form_screen.dart';
import 'mover_row.dart';

/// Opens the report for the budget month [month] over the app.
Future<void> openLabReport(BuildContext context, BudgetMonth month) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LabReportScreen(month: month)),
  );
}

/// One finished budget month on a page: what came in and went out against the
/// month before, how the budgets did, what moved, the biggest expenses, how
/// spending ran through the days, and what to do next. A section with nothing
/// to say is left out. Opening it counts as having read it, so Home stops
/// announcing it.
class LabReportScreen extends ConsumerStatefulWidget {
  const LabReportScreen({super.key, required this.month});

  final BudgetMonth month;

  @override
  ConsumerState<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends ConsumerState<LabReportScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: changing a setting while building is rejected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) markReportSeen(ref, widget.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = ref.watch(copyProvider);
    final report = ref.watch(labReportProvider(widget.month));

    final Widget body;
    if (report.hasError && !report.isLoading) {
      body = EmptyState(
        key: const ValueKey('report-error'),
        icon: Icons.error_outline,
        message: 'Could not load this report.',
        actionLabel: 'Try again',
        onAction: () => reloadReports(ref),
      );
    } else if (report.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _ReportBody(report: report.value!);
    }
    return Scaffold(
      appBar: AppBar(title: Text(copy.reportTitle)),
      body: body,
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.report});

  final LabReport report;

  static String _monthName(BudgetMonth m) =>
      DateFormat.MMMM().format(DateTime(m.year, m.month));

  /// "$50.00 more than August", or "The same as August".
  static String _against(int delta, String symbol, String previous) {
    if (delta == 0) return 'The same as $previous';
    final amount = formatMoney(delta.abs(), symbol);
    return '$amount ${delta > 0 ? 'more' : 'less'} than $previous';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final startDay = ref.watch(monthStartDayProvider);
    final t = report.totals;
    final before = report.previous;
    final beforeName = before == null ? '' : _monthName(before.month);
    String? versus(int Function(MonthTotals) of) => before == null
        ? null
        : _against(of(t) - of(before), symbol, beforeName);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(
          DateFormat.yMMMM().format(
            DateTime(report.month.year, report.month.month),
          ),
          key: const ValueKey('report-month'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          formatRange(report.month.range(startDay)),
          style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
        ),
        const SizedBox(height: Gap.l),
        const SectionLabel('The month'),
        const SizedBox(height: Gap.s),
        FactRow(
          label: 'Received',
          subtitle: versus((m) => m.receivedCents),
          value: formatMoney(t.receivedCents, symbol, showPlus: true),
        ),
        FactRow(
          label: 'Spent',
          subtitle: versus((m) => m.spentCents),
          value: formatMoney(-t.spentCents, symbol),
        ),
        FactRow(
          label: 'Net',
          subtitle: versus((m) => m.netCents),
          value: formatMoney(t.netCents, symbol, showPlus: true),
        ),
        FactRow(
          label: copy.purityName,
          subtitle: before?.purity == null
              ? null
              : '$beforeName: ${purityText(before!.purity!)}',
          value: t.purity == null ? 'nothing received' : purityText(t.purity!),
          valueIsPlain: t.purity == null,
        ),
        ..._budgets(context, ref, symbol),
        ..._movers(context, symbol),
        ..._biggest(context, symbol),
        ..._rhythm(symbol),
        ..._next(context, ref, symbol),
      ],
    );
  }

  List<Widget> _budgets(BuildContext context, WidgetRef ref, String symbol) {
    if (report.budgets.isEmpty) return const [];
    final inForce = {
      for (final line
          in ref.watch(budgetOverviewProvider).value?.all ??
              const <BudgetLine>[])
        line.categoryId: line,
    };

    Widget tile(ReportBudget b) {
      final line = inForce[b.categoryId];
      final last = report.lastPeriods[b.categoryId];
      final single = b.periods == 1;
      final amounts =
          '${formatMoney(b.spentCents, symbol)} of '
          '${formatMoney(b.limitCents, symbol)}';
      final subtitle = single ? amounts : '$amounts in ${b.periods} periods';
      final String value;
      if (single) {
        value = b.wentOver
            ? 'Over by ${formatMoney(b.overCents, symbol)}'
            : '${formatMoney(b.leftCents, symbol)} under';
      } else {
        value = b.wentOver
            ? 'Over in ${b.overPeriods} of ${b.periods}'
            : 'Within the limit every time';
      }
      String? actionLabel;
      VoidCallback? action;
      if (line != null) {
        actionLabel = 'Adjust';
        action = () => showBudgetEditor(
          context,
          categoryId: b.categoryId,
          name: b.name,
          current: line,
        );
      } else if (last != null && !(last.category?.isArchived ?? false)) {
        actionLabel = 'Copy forward';
        action = () => showBudgetEditor(
          context,
          categoryId: b.categoryId,
          name: b.name,
          copyFrom: last,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FactRow(
            key: ValueKey('report-budget-${b.categoryId ?? 0}'),
            label: b.name,
            subtitle: subtitle,
            value: value,
            valueIsPlain: !single,
          ),
          if (actionLabel != null)
            TextButton(
              key: ValueKey('report-budget-action-${b.categoryId ?? 0}'),
              onPressed: action,
              child: Text(actionLabel),
            ),
        ],
      );
    }

    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('Budgets'),
      const SizedBox(height: Gap.s),
      for (final b in report.budgets) tile(b),
    ];
  }

  List<Widget> _movers(BuildContext context, String symbol) {
    if (report.up.isEmpty && report.down.isEmpty) return const [];
    final theme = Theme.of(context);
    final c = context.appColors;
    final n = report.monthsAveraged;
    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('What moved'),
      const SizedBox(height: Gap.xs),
      Text(
        'Against the $n month${n == 1 ? '' : 's'} before it.',
        style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
      ),
      const SizedBox(height: Gap.s),
      for (final m in report.up) MoverRow(move: m, up: true, symbol: symbol),
      for (final m in report.down) MoverRow(move: m, up: false, symbol: symbol),
    ];
  }

  List<Widget> _biggest(BuildContext context, String symbol) {
    if (report.biggest.isEmpty) return const [];
    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('Biggest expenses'),
      const SizedBox(height: Gap.s),
      for (final tx in report.biggest)
        FactRow(
          key: ValueKey('report-expense-${tx.transaction.id}'),
          label: tx.transaction.title ?? tx.category.name,
          subtitle:
              '${tx.category.name} · '
              '${formatDate(fromIsoDate(tx.transaction.date))}',
          value: formatMoney(-tx.transaction.amountCents, symbol),
          onTap: () => showTransactionForm(context, editId: tx.transaction.id),
        ),
    ];
  }

  List<Widget> _rhythm(String symbol) {
    final r = report.rhythm;
    if (r == null) return const [];
    String days(int n) => '$n day${n == 1 ? '' : 's'}';
    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('How it ran'),
      const SizedBox(height: Gap.s),
      FactRow(
        label: 'Average a day',
        value: formatMoney(-r.averagePerDayCents, symbol),
      ),
      if (r.busiestDay != null)
        FactRow(
          label: 'Busiest day',
          subtitle: formatDate(r.busiestDay!),
          value: formatMoney(-r.busiestDayCents, symbol),
        ),
      FactRow(
        label: 'Days with no spending',
        subtitle: 'of ${days(r.days)}',
        value: '${r.noSpendDays}',
      ),
      FactRow(
        label: 'Longest run with none',
        value: days(r.longestNoSpendStreak),
        valueIsPlain: true,
      ),
    ];
  }

  List<Widget> _next(BuildContext context, WidgetRef ref, String symbol) {
    if (report.suggestions.isEmpty) return const [];
    final theme = Theme.of(context);

    Widget row({
      required Key key,
      required String text,
      required String action,
      required VoidCallback onPressed,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          TextButton(key: key, onPressed: onPressed, child: Text(action)),
        ],
      ),
    );

    return [
      const SizedBox(height: Gap.xl),
      const SectionLabel('Next'),
      const SizedBox(height: Gap.s),
      for (final s in report.suggestions)
        switch (s) {
          SetLimitSuggestion() => row(
            key: ValueKey('report-set-limit-${s.categoryId}'),
            text:
                '${s.name} took ${formatMoney(s.spentCents, symbol)} and has '
                'no budget.',
            action: 'Set a limit',
            onPressed: () => showBudgetEditor(
              context,
              categoryId: s.categoryId,
              name: s.name,
            ),
          ),
          BackUpSuggestion() => row(
            key: const ValueKey('report-backup'),
            text: 'There is no recent backup of your data.',
            action: 'Back up now',
            onPressed: () => backUpNow(context, ref),
          ),
        },
    ];
  }
}
