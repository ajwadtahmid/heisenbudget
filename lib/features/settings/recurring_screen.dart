import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';
import '../shared/recurring_catch_up.dart';
import '../shared/empty_state.dart';
import 'recurring_editor_screen.dart';

/// Every repeating transaction, with a switch to pause each one.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider).value ?? const [];
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final c = context.appColors;
    final theme = Theme.of(context);

    CategoryRow? categoryOf(RecurringRuleRow rule) {
      for (final cat in categories) {
        if (cat.id == rule.categoryId) return cat;
      }
      return null;
    }

    // Running ones by next date first, then paused, then ended.
    int rank(RecurringRuleRow r) => r.hasEnded ? 2 : (r.isActive ? 0 : 1);
    final sorted = [...rules]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        final da = a.nextDate, db = b.nextDate;
        if (da != null && db != null) {
          final byDate = da.compareTo(db);
          if (byDate != 0) return byDate;
        }
        return a.id.compareTo(b.id);
      });

    final failed = ref.watch(recurringCatchUpFailuresProvider) > 0;
    final content = sorted.isEmpty
        ? const EmptyState(
            icon: Icons.repeat,
            message:
                'Nothing repeats yet.\nTurn on Repeat when you add a '
                'transaction, such as rent or a salary.',
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              for (final rule in sorted)
                _RuleTile(
                  key: ValueKey('rule-${rule.id}'),
                  rule: rule,
                  category: categoryOf(rule),
                  symbol: symbol,
                  colors: c,
                  theme: theme,
                ),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Repeating transactions')),
      body: failed
          ? Column(
              children: [
                _CatchUpNotice(
                  onRetry: () => runRecurringCatchUp(ref),
                  colors: c,
                ),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}

/// Shown while the check for due repeating transactions is failing.
class _CatchUpNotice extends StatelessWidget {
  const _CatchUpNotice({required this.onRetry, required this.colors});

  final VoidCallback onRetry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('recurring-notice'),
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(Radii.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Repeating transactions could not be added the last time the app '
            'checked. Nothing was lost.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('recurring-retry'),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({
    super.key,
    required this.rule,
    required this.category,
    required this.symbol,
    required this.colors,
    required this.theme,
  });

  final RecurringRuleRow rule;
  final CategoryRow? category;
  final String symbol;
  final AppColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = rule.type == TransactionType.income;
    final amount = formatMoney(
      isIncome ? rule.amountCents : -rule.amountCents,
      symbol,
      showPlus: true,
    );
    final next = rule.nextDate;
    final status = rule.hasEnded
        ? 'Ended'
        : !rule.isActive
        ? 'Paused'
        : 'Next ${formatDate(next!)}';
    final name =
        rule.title ?? rule.note ?? category?.name ?? 'Repeating transaction';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 10,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecurringEditorScreen(ruleId: rule.id),
          ),
        ),
        leading: CategoryTile(
          iconKey: category?.icon ?? 'category',
          archived: category?.isArchived ?? false,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${rule.recurrence.scheduleText}\n$status · $amount',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Switch(
          key: ValueKey('rule-switch-${rule.id}'),
          value: rule.isActive,
          onChanged: rule.hasEnded
              ? null
              : (v) =>
                    ref.read(recurringRepositoryProvider).setActive(rule.id, v),
        ),
      ),
    );
  }
}
