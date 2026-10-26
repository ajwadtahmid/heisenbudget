import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/iso_date.dart';
import '../../domain/search.dart';
import '../../domain/transaction_type.dart';
import 'category_tile.dart';
import 'highlighted_text.dart';

/// One ledger row: icon square, category, date and note, and the amount in
/// tabular mono on the right, closed by a hairline.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.item,
    required this.currencySymbol,
    this.onTap,
    this.onLongPress,
    this.highlight,
    this.showDate = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final TransactionWithCategory item;
  final String currencySymbol;
  final VoidCallback? onTap;

  /// Opens the row's menu (edit, duplicate, favorite, delete).
  final VoidCallback? onLongPress;

  /// Search words to emphasise in the category and note.
  final SearchQuery? highlight;

  /// Home shows the date under each row; History groups by day instead.
  final bool showDate;

  /// Horizontal inset of the row. Pass [EdgeInsets.zero] inside a list that
  /// already has its own padding.
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final tx = item.transaction;
    final category = item.category;
    final isIncome = tx.type == TransactionType.income;
    final c = context.appColors;
    final theme = Theme.of(context);

    // Received/Spent are never told apart by colour alone: + and - as well.
    final signed = isIncome ? tx.amountCents : -tx.amountCents;
    final amount = formatMoney(signed, currencySymbol, showPlus: true);

    // A small mark when a repeating rule made this one.
    final repeats = tx.recurringRuleId != null;
    final subtitleParts = [
      if (showDate) formatDate(fromIsoDate(tx.date)),
      if (tx.note != null) tx.note!,
    ];

    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          contentPadding: contentPadding,
          minVerticalPadding: 10,
          leading: CategoryTile(
            iconKey: category.icon,
            archived: category.isArchived,
          ),
          title: HighlightedText(
            category.isArchived ? '${category.name} (archived)' : category.name,
            query: highlight,
          ),
          subtitle: subtitleParts.isEmpty && !repeats
              ? null
              : Row(
                  children: [
                    if (repeats) ...[
                      Icon(
                        Icons.repeat,
                        size: 14,
                        color: c.dim,
                        semanticLabel: 'Repeating',
                      ),
                      if (subtitleParts.isNotEmpty) const SizedBox(width: 4),
                    ],
                    if (subtitleParts.isNotEmpty)
                      Flexible(
                        child: HighlightedText(
                          subtitleParts.join(' · '),
                          query: highlight,
                        ),
                      ),
                  ],
                ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amount,
                style: monoText(
                  size: 16,
                  color: isIncome ? c.received : c.spent,
                ),
              ),
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
