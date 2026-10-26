import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/week_mode.dart';
import '../../providers/category_providers.dart';
import '../../providers/favorite_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'backup_section.dart';
import 'category_manager_screen.dart';
import 'favorites_screen.dart';
import 'money_dates_screen.dart';
import 'recurring_screen.dart';
import 'settings_widgets.dart';

String _ruleCount(int n) => switch (n) {
  0 => 'Rent, salary, subscriptions',
  1 => '1 repeating transaction',
  _ => '$n repeating transactions',
};

String _favoriteCount(int n) => switch (n) {
  0 => 'One tap to log what you buy often',
  1 => '1 favorite',
  _ => '$n favorites',
};

String _categoryCount(int n) => n == 1 ? '1 category' : '$n categories';

/// The Settings tab: a short page. The things used often (managing data,
/// backup) are right here; the set-once preferences are one tap away.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    final rules = ref.watch(recurringRulesProvider).value ?? const [];
    final favorites = ref.watch(favoritesProvider).value ?? const [];

    final mode = settings.themeMode.name;
    final appearance =
        '${mode[0].toUpperCase()}${mode.substring(1)} · '
        '${settings.accent.label} · ${settings.textFont.label}';
    final money = settings.weekMode == WeekMode.calendar
        ? '${settings.currency.code} · weeks start '
              '${weekdayNames[settings.weekStartDay - 1]}'
        : '${settings.currency.code} · fixed 7-day blocks';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          SettingsGroup(
            label: 'Appearance and numbers',
            children: [
              SettingsRow(
                key: const ValueKey('settings-appearance'),
                icon: Icons.palette_outlined,
                title: 'Appearance',
                summary: appearance,
                chevron: true,
                onTap: () =>
                    pushSettingsPage(context, const AppearanceScreen()),
              ),
              SettingsRow(
                key: const ValueKey('settings-money'),
                icon: Icons.payments_outlined,
                title: 'Money & dates',
                summary: money,
                chevron: true,
                onTap: () =>
                    pushSettingsPage(context, const MoneyDatesScreen()),
              ),
            ],
          ),
          SettingsGroup(
            label: 'Manage',
            children: [
              SettingsRow(
                key: const ValueKey('manage-categories'),
                icon: Icons.category_outlined,
                title: 'Manage categories',
                summary: _categoryCount(
                  categories.where((cat) => !cat.isArchived).length,
                ),
                chevron: true,
                onTap: () =>
                    pushSettingsPage(context, const CategoryManagerScreen()),
              ),
              SettingsRow(
                key: const ValueKey('manage-recurring'),
                icon: Icons.repeat,
                title: 'Repeating transactions',
                summary: _ruleCount(rules.length),
                chevron: true,
                onTap: () => pushSettingsPage(context, const RecurringScreen()),
              ),
              SettingsRow(
                key: const ValueKey('manage-favorites'),
                icon: Icons.bolt_outlined,
                title: 'Favorites',
                summary: _favoriteCount(favorites.length),
                chevron: true,
                onTap: () => pushSettingsPage(context, const FavoritesScreen()),
              ),
            ],
          ),
          const SettingsGroup(label: 'Your data', children: [BackupSection()]),
          SettingsGroup(
            label: 'About',
            children: [
              SettingsRow(
                key: const ValueKey('settings-about'),
                icon: Icons.info_outline,
                title: 'About $appName',
                summary: 'Version $appVersion',
                chevron: true,
                onTap: () => pushSettingsPage(context, const AboutScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
