import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../shared/category_tile.dart';
import '../transaction_form/new_category_dialog.dart';

/// Add, rename, archive and restore categories. Two tabs: Expense, Income.
class CategoryManagerScreen extends StatelessWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CategoryList(type: TransactionType.expense),
            _CategoryList(type: TransactionType.income),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = (ref.watch(allCategoriesProvider).value ?? const [])
        .where((c) => c.type == type)
        .toList();
    final active = all.where((c) => !c.isArchived).toList();
    final archived = all.where((c) => c.isArchived).toList();
    final repo = ref.read(categoryRepositoryProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        key: ValueKey('add-category-${type.name}'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () => showCategoryNameDialog(context, type: type),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final c in active)
            ListTile(
              key: ValueKey('category-row-${c.id}'),
              // A hairline closes each row, like every other ledger in the app.
              shape: Border(
                bottom: BorderSide(color: context.appColors.hairline),
              ),
              leading: CategoryTile(iconKey: c.icon),
              title: Text(c.name),
              subtitle: c.isProtected ? const Text('Always available') : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "Other" can change its icon but not its name or archive.
                  IconButton(
                    tooltip: 'Edit ${c.name}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showCategoryNameDialog(
                      context,
                      type: type,
                      existing: c,
                    ),
                  ),
                  if (!c.isProtected && active.length > 1)
                    IconButton(
                      key: ValueKey('merge-${c.id}'),
                      tooltip: 'Merge ${c.name} into another',
                      icon: const Icon(Icons.merge_type),
                      onPressed: () => _merge(context, repo, c, [
                        for (final other in active)
                          if (other.id != c.id) other,
                      ]),
                    ),
                  if (!c.isProtected)
                    IconButton(
                      tooltip: 'Archive ${c.name}',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: () => _archive(context, repo, c),
                    ),
                ],
              ),
            ),
          if (archived.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text(
                'Archived',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final c in archived)
              ListTile(
                key: ValueKey('category-row-${c.id}'),
                // A hairline closes each row, like every other ledger in the app.
                shape: Border(
                  bottom: BorderSide(color: context.appColors.hairline),
                ),
                leading: CategoryTile(iconKey: c.icon, archived: true),
                title: Text(c.name),
                trailing: IconButton(
                  tooltip: 'Restore ${c.name}',
                  icon: const Icon(Icons.unarchive_outlined),
                  onPressed: () => repo.restore(c.id),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Moves everything in [from] to a category the person picks, then archives
  /// it. It cannot be undone, so it asks twice: where, then to confirm.
  Future<void> _merge(
    BuildContext context,
    CategoryRepository repo,
    CategoryRow from,
    List<CategoryRow> targets,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final into = await showDialog<CategoryRow>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Merge "${from.name}" into'),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              key: ValueKey('merge-into-${target.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(target),
              child: Row(
                children: [
                  CategoryTile(iconKey: target.icon, size: 32),
                  const SizedBox(width: Gap.m),
                  Expanded(child: Text(target.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (into == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Merge into "${into.name}"?'),
        content: Text(
          'Every transaction, repeating transaction and favorite in '
          '"${from.name}" moves to "${into.name}", and "${from.name}" is '
          'archived. A budget limit moves too, unless "${into.name}" already '
          'has its own. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('merge-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final moved = await repo.merge(fromId: from.id, intoId: into.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              moved == 1
                  ? 'Moved 1 transaction to "${into.name}"'
                  : 'Moved $moved transactions to "${into.name}"',
            ),
          ),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not merge. Nothing was changed.'),
          ),
        );
    }
  }

  Future<void> _archive(
    BuildContext context,
    CategoryRepository repo,
    CategoryRow category,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await repo.archive(category.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Archived "${category.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restore(category.id),
          ),
        ),
      );
  }
}
