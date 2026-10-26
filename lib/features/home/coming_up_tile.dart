import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/transaction_type.dart';
import '../../providers/recurring_providers.dart';
import '../settings/recurring_editor_screen.dart';
import '../shared/category_tile.dart';

/// One repeating transaction due in the next few days. It is a heads-up only:
/// it is not in any total until it is actually added.
class ComingUpTile extends StatelessWidget {
  const ComingUpTile({
    super.key,
    required this.item,
    required this.currencySymbol,
    required this.today,
  });

  final ComingUp item;
  final String currencySymbol;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rule = item.rule;
    final c = context.appColors;
    final theme = Theme.of(context);
    final isIncome = rule.type == TransactionType.income;
    final days = DateTime.utc(
      item.date.year,
      item.date.month,
      item.date.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final when = days == 1 ? 'tomorrow' : 'in $days days';
    final name = rule.note ?? item.category?.name ?? 'Repeating transaction';
    final amount = formatMoney(
      isIncome ? rule.amountCents : -rule.amountCents,
      currencySymbol,
      showPlus: true,
    );

    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hairline)),
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
            iconKey: item.category?.icon ?? 'category',
            archived: item.category?.isArchived ?? false,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${formatDate(item.date)} · $when',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              // Dim, not green or amber: nothing has happened yet.
              child: Text(amount, style: monoText(size: 16, color: c.dim)),
            ),
          ),
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            color: c.text,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
