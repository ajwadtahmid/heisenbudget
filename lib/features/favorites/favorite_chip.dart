import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../providers/category_providers.dart';
import '../../providers/favorite_providers.dart';
import '../../providers/settings_providers.dart';
import '../favorites/favorite_editor.dart';
import '../favorites/quick_log.dart';

/// The Quick add strip on Home: one button per favorite. Tapping logs it
/// dated today (with Undo); long-pressing offers to open or edit it. Shows
/// nothing at all until there is a favorite.
class QuickAddStrip extends ConsumerWidget {
  const QuickAddStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    if (favorites.isEmpty) return const SizedBox.shrink();
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Gap.xl),
        const SectionLabel('Quick add'),
        const SizedBox(height: Gap.m),
        Wrap(
          spacing: Gap.m,
          runSpacing: Gap.m,
          children: [
            for (final favorite in favorites)
              FavoriteChip(
                key: ValueKey('favorite-${favorite.id}'),
                favorite: favorite,
                iconKey: categories
                    .where((c) => c.id == favorite.categoryId)
                    .map((c) => c.icon)
                    .firstOrNull,
                symbol: symbol,
                onTap: () => useFavorite(context, ref, favorite),
                onLongPress: () => _showOptions(context, ref, favorite),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showOptions(
    BuildContext context,
    WidgetRef ref,
    FavoriteRow favorite,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.s),
                child: Text(
                  favorite.label,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                key: const ValueKey('favorite-open'),
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open in the Add sheet'),
                subtitle: const Text('Change it before saving'),
                onTap: () {
                  close();
                  openFavoriteInForm(context, ref, favorite);
                },
              ),
              ListTile(
                key: const ValueKey('favorite-edit'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit this favorite'),
                onTap: () {
                  close();
                  showFavoriteEditor(context, existing: favorite);
                },
              ),
              const SizedBox(height: Gap.s),
            ],
          ),
        );
      },
    );
  }
}

/// One favorite as a button: category icon, name and, when it has one, the
/// amount in mono. 48dp tall; wraps onto the next line instead of overflowing.
class FavoriteChip extends StatelessWidget {
  const FavoriteChip({
    super.key,
    required this.favorite,
    required this.iconKey,
    required this.symbol,
    required this.onTap,
    required this.onLongPress,
  });

  final FavoriteRow favorite;
  final String? iconKey;
  final String symbol;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final cents = favorite.amountCents;
    final amount = cents == null ? null : formatMoney(cents, symbol);
    final radius = BorderRadius.circular(Radii.chip);

    return Semantics(
      container: true,
      button: true,
      label: amount == null
          ? '${favorite.label}. Opens the Add sheet to enter the amount.'
          : '${favorite.label}, $amount. Logs it today.',
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: 'Options',
      child: ExcludeSemantics(
        child: Material(
          color: c.panel,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.hairline),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(categoryIconFor(iconKey).icon, size: 18, color: c.dim),
                    const SizedBox(width: Gap.s),
                    Flexible(
                      child: Text(
                        favorite.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (amount != null) ...[
                      const SizedBox(width: Gap.s),
                      Text(amount, style: monoText(size: 13, color: c.dim)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
