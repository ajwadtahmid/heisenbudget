import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/database_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../favorites/favorite_editor.dart';
import '../transaction_form/transaction_draft.dart';
import '../transaction_form/transaction_form_screen.dart';

/// Deletes a transaction and offers Undo, from the app-wide snackbar host.
Future<void> deleteTransactionWithUndo(
  WidgetRef ref,
  TransactionWithCategory item,
) async {
  final repo = ref.read(transactionRepositoryProvider);
  final messenger = ref.read(rootMessengerKeyProvider);
  final backup = TransactionInput.fromRow(item.transaction);
  await repo.delete(item.transaction.id);
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.add(backup),
        ),
      ),
    );
}

/// The menu a long-press on a transaction row opens: Edit, Duplicate, Save as
/// favorite and Delete. The same actions are in the Edit sheet's header menu.
Future<void> showTransactionMenu(
  BuildContext context,
  WidgetRef ref,
  TransactionWithCategory item,
) {
  final symbol = ref.read(settingsProvider).currencySymbol;
  final tx = item.transaction;
  final signed = tx.type == TransactionType.income
      ? tx.amountCents
      : -tx.amountCents;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      void close() => Navigator.of(sheetContext).pop();
      final theme = Theme.of(sheetContext);
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.s),
              child: Text(
                '${tx.title ?? item.category.name}  ${formatMoney(signed, symbol, showPlus: true)}',
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              key: const ValueKey('menu-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                close();
                showTransactionForm(context, editId: tx.id);
              },
            ),
            ListTile(
              key: const ValueKey('menu-duplicate'),
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              subtitle: const Text('A new one dated today'),
              onTap: () {
                close();
                showTransactionForm(
                  context,
                  draft: TransactionDraft.fromTransaction(item),
                );
              },
            ),
            ListTile(
              key: const ValueKey('menu-favorite'),
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Save as favorite'),
              subtitle: const Text('One tap on Home to log it again'),
              onTap: () {
                close();
                showFavoriteEditor(
                  context,
                  from: TransactionDraft.fromTransaction(item),
                );
              },
            ),
            ListTile(
              key: const ValueKey('menu-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: context.appColors.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: context.appColors.error),
              ),
              onTap: () {
                close();
                deleteTransactionWithUndo(ref, item);
              },
            ),
            const SizedBox(height: Gap.s),
          ],
        ),
      );
    },
  );
}
