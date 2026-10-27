import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../providers/category_providers.dart';
import '../../providers/favorite_providers.dart';
import '../../providers/settings_providers.dart';
import '../favorites/favorite_editor.dart';
import '../shared/category_tile.dart';
import '../shared/empty_state.dart';

/// The Quick add list: reorder with the handles, edit or delete each one.
/// New favorites are made from a transaction ("Save as favorite").
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final c = context.appColors;

    CategoryRow? categoryOf(FavoriteRow f) =>
        categories.where((cat) => cat.id == f.categoryId).firstOrNull;

    Future<void> confirmDelete(FavoriteRow favorite) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Delete “${favorite.label}”?'),
          content: const Text(
            'It leaves the Quick add strip. Transactions you logged with it '
            'stay in History.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('favorite-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await ref.read(favoriteRepositoryProvider).delete(favorite.id);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Quick add')),
      body: favorites.isEmpty
          ? const EmptyState(
              icon: Icons.bolt_outlined,
              message:
                  'No favorites yet.\nPress and hold a transaction, then '
                  'choose Save as favorite.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, Gap.s),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${favorites.length} of $maxFavorites. Drag the handles '
                      'to reorder.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: c.dim),
                    ),
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('favorite-shortcut'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text('Launcher shortcut'),
                  subtitle: const Text(
                    'Show the first favorite when you press and hold the app '
                    'icon. Its name is visible there, so turn this off to '
                    'keep it private.',
                  ),
                  value: ref.watch(
                    settingsProvider.select((s) => s.favoriteShortcut),
                  ),
                  onChanged: (on) => ref
                      .read(settingsProvider.notifier)
                      .setFavoriteShortcut(on),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 40),
                    buildDefaultDragHandles: false,
                    itemCount: favorites.length,
                    onReorderItem: (from, to) {
                      final ids = [for (final f in favorites) f.id];
                      ids.insert(to, ids.removeAt(from));
                      ref.read(favoriteRepositoryProvider).reorder(ids);
                    },
                    itemBuilder: (context, index) {
                      final favorite = favorites[index];
                      final cents = favorite.amountCents;
                      return DecoratedBox(
                        key: ValueKey('favorite-row-${favorite.id}'),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.hairline)),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          minVerticalPadding: 10,
                          onTap: () =>
                              showFavoriteEditor(context, existing: favorite),
                          leading: CategoryTile(
                            iconKey: categoryOf(favorite)?.icon ?? 'category',
                            archived: categoryOf(favorite)?.isArchived ?? false,
                          ),
                          title: Text(
                            favorite.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            cents == null
                                ? 'Amount each time'
                                : formatMoney(cents, symbol),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey('favorite-delete-${favorite.id}'),
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => confirmDelete(favorite),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Icon(
                                    Icons.drag_handle,
                                    semanticLabel: 'Drag to reorder',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
