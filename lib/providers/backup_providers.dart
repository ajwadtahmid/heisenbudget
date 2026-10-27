import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_service.dart';
import '../data/backup/file_exchange.dart';
import '../domain/backup_status.dart';
import 'database_providers.dart';
import 'period_providers.dart';
import 'settings_providers.dart';
import 'transaction_providers.dart';

/// Share sheet and file picker. Tests override it with a fake.
final fileExchangeProvider = Provider<FileExchange>(
  (ref) => const FileExchange(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(settingsRepositoryProvider),
    files: ref.watch(databaseFilesProvider),
  ),
);

/// What Home says when a backup is due: how old the last one is, or that
/// there has never been one.
class BackupReminder {
  const BackupReminder({required this.daysSince});

  /// Days since the last backup; null when there has never been one.
  final int? daysSince;
}

/// The reminder to show on Home, or null when none is due. Counts as quiet
/// while the number of transactions is still loading.
final backupReminderProvider = Provider<BackupReminder?>((ref) {
  final settings = ref.watch(settingsProvider);
  final today = ref.watch(clockProvider);
  final count = ref.watch(transactionCountProvider).value ?? 0;
  final last = settings.lastBackupAt;
  final due = backupReminderDue(
    enabled: settings.backupReminders,
    lastBackup: last,
    today: today,
    snoozedUntil: settings.backupSnoozedUntil,
    transactionCount: count,
  );
  if (!due) return null;
  return BackupReminder(
    daysSince: last == null ? null : daysSinceBackup(last, today),
  );
});
