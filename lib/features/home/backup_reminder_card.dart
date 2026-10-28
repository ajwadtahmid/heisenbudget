import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/backup_status.dart';
import '../../providers/backup_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../settings/backup_actions.dart';

/// A quiet card on Home when a backup is due (see [backupReminderDue]): it
/// says how old the last backup is and offers to make one now, later, or never
/// again. Nothing at all when no backup is due. It is only a card: the app
/// sends no notification and asks for no permission.
class BackupReminderCard extends ConsumerWidget {
  const BackupReminderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminder = ref.watch(backupReminderProvider);
    if (reminder == null) return const SizedBox.shrink();
    final c = context.appColors;
    final theme = Theme.of(context);
    final days = reminder.daysSince;
    final title = days == null ? 'Back up your data' : 'Time for a backup';
    final body = days == null
        ? 'You have not saved a backup yet. If this phone is lost or reset, '
              'your data goes with it.'
        : 'Your last backup is $days days old.';

    Future<void> later() => ref
        .read(settingsProvider.notifier)
        .setBackupSnoozedUntil(
          ref.read(clockProvider).add(const Duration(days: backupSnoozeDays)),
        );

    Future<void> stop() async {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(settingsProvider.notifier).setBackupReminders(false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Backup reminders are off. You can turn them on again in '
              'Settings.',
            ),
          ),
        );
    }

    return Semantics(
      container: true,
      label: '$title. $body',
      child: Container(
        key: const ValueKey('backup-reminder'),
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
                Icon(Icons.save_outlined, size: 20, color: c.dim),
                const SizedBox(width: Gap.m),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.s),
            // Wraps to more lines at large text instead of overflowing.
            OverflowBar(
              alignment: MainAxisAlignment.start,
              spacing: Gap.s,
              overflowSpacing: Gap.xs,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('reminder-backup-now'),
                  onPressed: () => backUpNow(context, ref),
                  child: const Text('Back up now'),
                ),
                TextButton(
                  key: const ValueKey('reminder-later'),
                  onPressed: later,
                  child: const Text('Remind me later'),
                ),
                TextButton(
                  key: const ValueKey('reminder-off'),
                  onPressed: stop,
                  child: const Text('Stop reminding me'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
