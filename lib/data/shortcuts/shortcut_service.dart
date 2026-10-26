import 'package:quick_actions/quick_actions.dart';

import '../../domain/quick_add.dart';

/// One entry in the launcher's long-press menu.
class AppShortcut {
  const AppShortcut({
    required this.type,
    required this.title,
    required this.icon,
  });

  final String type;
  final String title;

  /// A native resource name (Android drawable, iOS image asset).
  final String icon;

  @override
  bool operator ==(Object other) =>
      other is AppShortcut &&
      other.type == type &&
      other.title == title &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(type, title, icon);
}

/// Add expense and Add income, plus one for [topFavoriteLabel] (the first
/// favorite on Home) when there is one. The favorite shortcut only opens the
/// Add sheet filled in; it never logs money by itself.
List<AppShortcut> buildShortcuts({
  int? topFavoriteId,
  String? topFavoriteLabel,
}) {
  return [
    const AppShortcut(
      type: shortcutAddExpense,
      title: 'Add expense',
      icon: 'ic_shortcut_expense',
    ),
    const AppShortcut(
      type: shortcutAddIncome,
      title: 'Add income',
      icon: 'ic_shortcut_income',
    ),
    if (topFavoriteId != null && topFavoriteLabel != null)
      AppShortcut(
        type: '$shortcutFavoritePrefix$topFavoriteId',
        title: 'Add $topFavoriteLabel',
        icon: 'ic_shortcut_favorite',
      ),
  ];
}

/// The phone's launcher shortcuts. The only place that talks to the
/// `quick_actions` plugin; tests replace it with a fake.
class ShortcutService {
  const ShortcutService();

  static const _plugin = QuickActions();

  /// Starts listening. [onAction] gets a shortcut's type when it is chosen,
  /// whether the app was closed or already running.
  Future<void> start(void Function(String type) onAction) async {
    try {
      await _plugin.initialize(onAction);
    } catch (_) {
      // No launcher shortcuts on this platform: nothing to do.
    }
  }

  /// Replaces the shortcuts the launcher shows.
  Future<void> setShortcuts(List<AppShortcut> items) async {
    try {
      await _plugin.setShortcutItems([
        for (final item in items)
          ShortcutItem(
            type: item.type,
            localizedTitle: item.title,
            icon: item.icon,
          ),
      ]);
    } catch (_) {
      // Same: a platform without shortcuts is not an error.
    }
  }
}
