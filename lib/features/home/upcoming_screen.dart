import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/transaction_type.dart';
import '../../providers/period_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/empty_state.dart';
import 'coming_up_tile.dart';

/// Everything the repeating rules will add in the next 30, 60 or 90 days. A
/// plan only: none of it is in the balance or any total until its day comes.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  int _days = upcomingWindows.first;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(upcomingProvider(_days));
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final today = ref.watch(clockProvider);
    final theme = Theme.of(context);
    final c = context.appColors;

    var incoming = 0;
    var outgoing = 0;
    for (final item in items) {
      if (item.rule.type == TransactionType.income) {
        incoming += item.rule.amountCents;
      } else {
        outgoing += item.rule.amountCents;
      }
    }

    final children = <Widget>[];
    int? lastMonth;
    for (final item in items) {
      final month = item.date.year * 12 + item.date.month;
      if (month != lastMonth) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: lastMonth == null ? 0 : Gap.l),
            child: SectionLabel(formatMonth(item.date)),
          ),
        );
        lastMonth = month;
      }
      children.add(
        ComingUpTile(
          key: ValueKey('upcoming-${item.rule.id}-${item.date}'),
          item: item,
          currencySymbol: symbol,
          today: today,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            'Planned from your repeating transactions. None of it counts in '
            'your balance or totals until the day it is added.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
          const SizedBox(height: Gap.m),
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            children: [
              for (final days in upcomingWindows)
                ChoiceChip(
                  key: ValueKey('upcoming-$days'),
                  label: Text('Next $days days'),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                ),
            ],
          ),
          const SizedBox(height: Gap.m),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Gap.xl),
              child: EmptyState(
                icon: Icons.event_available_outlined,
                message: 'Nothing is due in this time.',
              ),
            )
          else ...[
            Text(
              'Planned: ${formatMoney(incoming, symbol, showPlus: true)} in, '
              '${formatMoney(-outgoing, symbol)} out'
              '${items.length >= upcomingLimit ? ' (first $upcomingLimit)' : ''}',
              key: const ValueKey('upcoming-totals'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.m),
            ...children,
          ],
        ],
      ),
    );
  }
}
