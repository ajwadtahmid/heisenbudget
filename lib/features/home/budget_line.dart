import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/budget_providers.dart';
import '../../providers/navigation_providers.dart';

/// The one budget line on Home: how many budgets are over, almost used up,
/// or that all are fine. Tapping it opens Budgets. Nothing at all when no
/// limits are set this month.
class HomeBudgetLine extends ConsumerWidget {
  const HomeBudgetLine({super.key});

  /// What the line says.
  static String textFor(BudgetSummary s) {
    if (s.over > 0) return '${s.over} over budget';
    if (s.almost > 0) {
      return s.almost == 1
          ? '1 almost at its limit'
          : '${s.almost} almost at their limit';
    }
    return 'All within budget';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(budgetSummaryProvider);
    if (summary == null) return const SizedBox.shrink();
    final c = context.appColors;
    final theme = Theme.of(context);
    final trouble = summary.over > 0;
    final text = textFor(summary);

    return Semantics(
      button: true,
      label: '$text. Opens Budgets.',
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('home-budget-line'),
          onTap: () => ref.read(shellTabProvider.notifier).select(budgetsTab),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(
                  trouble
                      ? Icons.error_outline
                      : Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: trouble ? c.error : c.dim,
                ),
                const SizedBox(width: Gap.m),
                Expanded(
                  child: Text(
                    text,
                    key: const ValueKey('home-budget-text'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: trouble ? c.text : c.dim,
                      fontWeight: trouble ? FontWeight.w700 : FontWeight.w500,
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
