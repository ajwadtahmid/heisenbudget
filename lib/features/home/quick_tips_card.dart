import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/settings_providers.dart';
import '../../providers/tips_providers.dart';

/// A quiet card on Home once logging is a habit: it names the shortcuts that
/// have not been used yet. Dismissed for good with one tap; nothing at all
/// when every one is already in use.
class QuickTipsCard extends ConsumerWidget {
  const QuickTipsCard({super.key});

  static String lineFor(QuickTip tip) => switch (tip) {
    QuickTip.favorites =>
      'Favorites: save an entry you repeat, then log it in one tap from the '
          'Add sheet. Press and hold any transaction to save it as one.',
    QuickTip.repeating =>
      'Repeat: turn on Repeat in the Add sheet for rent, pay or a '
          'subscription, and it is added on its day.',
    QuickTip.budgets =>
      'Budgets: set a limit for a category and see what is left and about '
          'how much you can spend a day.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tips = ref.watch(quickTipsProvider);
    if (tips.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('quick-tips'),
      margin: const EdgeInsets.only(bottom: Gap.l),
      padding: const EdgeInsets.all(Gap.l),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_outlined, size: 20, color: c.dim),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Text(
                  'Make logging faster',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(lineFor(tip), style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: Gap.s),
          TextButton(
            key: const ValueKey('quick-tips-dismiss'),
            onPressed: () =>
                ref.read(settingsProvider.notifier).setTipsDismissed(true),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
