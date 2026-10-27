// PURE DART: no Flutter imports. How old the last backup is.
import 'iso_date.dart';

/// After this many days without a backup, Settings says so.
const backupStaleDays = 30;

/// Someone who has never made a backup is reminded once there is this much
/// to lose; before that there is nothing worth nagging about.
const backupRemindAfterTransactions = 10;

/// "Remind me later" stays quiet for this many days.
const backupSnoozeDays = 7;

enum BackupFreshness { never, recent, stale }

/// Whole days from the day of [last] to [today] (calendar days, so a backup
/// at 23:59 is one day old at 00:01).
int daysSinceBackup(DateTime last, DateTime today) {
  final a = dateOnly(last.toLocal());
  final b = dateOnly(today);
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

BackupFreshness backupFreshness(DateTime? last, DateTime today) {
  if (last == null) return BackupFreshness.never;
  return daysSinceBackup(last, today) > backupStaleDays
      ? BackupFreshness.stale
      : BackupFreshness.recent;
}

/// Whether Home should remind the person to make a backup: the reminders are
/// on, it is not snoozed, and the last backup is stale, or there has never
/// been one and there are at least [backupRemindAfterTransactions]
/// transactions.
bool backupReminderDue({
  required bool enabled,
  required DateTime? lastBackup,
  required DateTime today,
  required DateTime? snoozedUntil,
  required int transactionCount,
}) {
  if (!enabled) return false;
  if (snoozedUntil != null &&
      dateOnly(today).isBefore(dateOnly(snoozedUntil))) {
    return false;
  }
  return switch (backupFreshness(lastBackup, today)) {
    BackupFreshness.never => transactionCount >= backupRemindAfterTransactions,
    BackupFreshness.recent => false,
    BackupFreshness.stale => true,
  };
}
