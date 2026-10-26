import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/week_mode.dart';
import '../../providers/settings_providers.dart';
import '../shared/appearance_pickers.dart';
import '../shared/opening_balance_dialog.dart';

/// Monday to Sunday, indexed from ISO weekday 1.
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Currency, opening balance, and how weeks are counted.
class MoneyDatesScreen extends ConsumerWidget {
  const MoneyDatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isCalendar = settings.weekMode == WeekMode.calendar;
    final theme = Theme.of(context);
    final c = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Money & dates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
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
              helperText: isCalendar
                  ? 'Also where weekly and 2-week budgets start'
                  : 'Home uses fixed blocks; weekly and 2-week budgets '
                        'still start on this day',
              helperMaxLines: 3,
            ),
            items: [
              for (var day = 1; day <= 7; day++)
                DropdownMenuItem(
                  value: day,
                  child: Text(weekdayNames[day - 1]),
                ),
            ],
            onChanged: (day) {
              if (day != null) notifier.setWeekStartDay(day);
            },
          ),
          const SizedBox(height: Gap.l),
          const SectionLabel('Budgets'),
          const SizedBox(height: Gap.m),
          DropdownButtonFormField<int>(
            key: ValueKey('month-start-${settings.monthStartDay}'),
            isExpanded: true,
            initialValue: settings.monthStartDay,
            decoration: const InputDecoration(
              labelText: 'Budget month starts on',
              helperText:
                  'Budgets count from this day each month, for pay days. '
                  'Changing it moves where past budget months begin.',
              helperMaxLines: 3,
            ),
            items: [
              for (var day = 1; day <= 28; day++)
                DropdownMenuItem(value: day, child: Text(_ordinal(day))),
            ],
            onChanged: (day) {
              if (day != null) notifier.setMonthStartDay(day);
            },
          ),
        ],
      ),
    );
  }
}

/// 1 -> "1st", 22 -> "22nd".
String _ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}
