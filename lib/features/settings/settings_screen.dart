import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/week_mode.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/appearance_pickers.dart';
import '../shared/opening_balance_dialog.dart';
import 'backup_section.dart';
import 'category_manager_screen.dart';
import 'recurring_screen.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _ruleCount(int n) => switch (n) {
  0 => 'Rent, salary, subscriptions',
  1 => '1 repeating transaction',
  _ => '$n repeating transactions',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isCalendar = settings.weekMode == WeekMode.calendar;
    final theme = Theme.of(context);
    final c = context.appColors;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const SectionLabel('Appearance'),
          const SizedBox(height: Gap.m),
          KeyedSubtree(
            key: const ValueKey('theme-mode'),
            child: ThemeModePicker(
              selected: settings.themeMode,
              onChanged: notifier.setThemeMode,
            ),
          ),
          label('Accent'),
          AccentPicker(
            selected: settings.accent,
            onChanged: notifier.setAccent,
          ),
          label('Text font'),
          FontPicker(
            selected: settings.textFont,
            onChanged: notifier.setTextFont,
          ),
          const SizedBox(height: Gap.s),
          Text(
            'Numbers always use Geist Mono so they line up.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Gap.s),
          SwitchListTile(
            key: const ValueKey('lab-flavor'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Lab flavor'),
            subtitle: const Text(
              'Playful instrument wording, such as PURITY and flat-line messages.',
            ),
            value: settings.labFlavor,
            onChanged: notifier.setLabFlavor,
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Money'),
          const SizedBox(height: Gap.m),
          KeyedSubtree(
            key: const ValueKey('currency-dropdown'),
            child: CurrencyDropdown(
              selected: settings.currency,
              onChanged: (currency) => notifier.setCurrencyCode(currency.code),
            ),
          ),
          const SizedBox(height: Gap.s),
          Text(
            'Only the symbol changes. Amounts are not converted.',
            style: theme.textTheme.bodySmall,
          ),
          ListTile(
            key: const ValueKey('opening-balance-tile'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Opening balance'),
            subtitle: Text(
              formatMoney(
                settings.openingBalanceCents,
                settings.currencySymbol,
              ),
              style: monoText(size: 14, color: c.dim),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final cents = await showOpeningBalanceDialog(
                context,
                initialCents: settings.openingBalanceCents,
                symbol: settings.currencySymbol,
              );
              if (cents != null) await notifier.setOpeningBalanceCents(cents);
            },
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Weeks'),
          const SizedBox(height: Gap.m),
          SegmentedButton<WeekMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: WeekMode.calendar,
                label: Text('Calendar weeks'),
              ),
              ButtonSegment(
                value: WeekMode.fixed,
                label: Text('Fixed 7-day blocks'),
              ),
            ],
            selected: {settings.weekMode},
            onSelectionChanged: (s) => notifier.setWeekMode(s.first),
          ),
          const SizedBox(height: Gap.l),
          DropdownButtonFormField<int>(
            key: ValueKey('week-start-${settings.weekStartDay}-$isCalendar'),
            // Expanded so long day names shrink instead of overflowing.
            isExpanded: true,
            initialValue: settings.weekStartDay,
            decoration: InputDecoration(
              labelText: 'Week starts on',
              helperText: isCalendar ? null : 'Only used with calendar weeks',
            ),
            items: [
              for (var day = 1; day <= 7; day++)
                DropdownMenuItem(
                  value: day,
                  child: Text(_weekdayNames[day - 1]),
                ),
            ],
            onChanged: isCalendar
                ? (day) {
                    if (day != null) notifier.setWeekStartDay(day);
                  }
                : null,
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Categories'),
          ListTile(
            key: const ValueKey('manage-categories'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoryManagerScreen(),
              ),
            ),
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Recurring'),
          ListTile(
            key: const ValueKey('manage-recurring'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.repeat),
            title: const Text('Repeating transactions'),
            subtitle: Text(
              _ruleCount(ref.watch(recurringRulesProvider).value?.length ?? 0),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecurringScreen()),
            ),
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Backup'),
          const BackupSection(),
          const SizedBox(height: Gap.l),
          const SectionLabel('About'),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text(appVersion),
          ),
        ],
      ),
    );
  }
}
