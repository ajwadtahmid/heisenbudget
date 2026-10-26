// PURE DART: no Flutter imports. How old the last backup is.
import 'iso_date.dart';

/// After this many days without a backup, Settings says so.
const backupStaleDays = 30;

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
