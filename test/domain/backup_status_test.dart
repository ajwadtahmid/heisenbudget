import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/backup_status.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

void main() {
  test('no backup yet', () {
    expect(backupFreshness(null, d(2026, 10, 25)), BackupFreshness.never);
  });

  test('a backup today or recently is recent', () {
    expect(
      backupFreshness(d(2026, 10, 25), d(2026, 10, 25)),
      BackupFreshness.recent,
    );
    expect(
      backupFreshness(d(2026, 10, 1), d(2026, 10, 25)),
      BackupFreshness.recent,
    );
  });

  test('exactly 30 days is still recent; 31 is stale', () {
    expect(daysSinceBackup(d(2026, 9, 25), d(2026, 10, 25)), 30);
    expect(
      backupFreshness(d(2026, 9, 25), d(2026, 10, 25)),
      BackupFreshness.recent,
    );
    expect(daysSinceBackup(d(2026, 9, 24), d(2026, 10, 25)), 31);
    expect(
      backupFreshness(d(2026, 9, 24), d(2026, 10, 25)),
      BackupFreshness.stale,
    );
  });

  test('days are calendar days, not 24-hour spans', () {
    expect(daysSinceBackup(d(2026, 10, 24, 23), d(2026, 10, 25)), 1);
    expect(daysSinceBackup(d(2026, 10, 25, 0), d(2026, 10, 25)), 0);
  });

  test('a daylight-saving change does not shift the count', () {
    expect(daysSinceBackup(d(2026, 3, 1), d(2026, 4, 1)), 31);
    expect(daysSinceBackup(d(2026, 10, 1), d(2026, 11, 10)), 40);
  });

  test('a backup dated in the future counts as zero or less, never stale', () {
    expect(
      backupFreshness(d(2026, 11, 1), d(2026, 10, 25)),
      BackupFreshness.recent,
    );
  });

  group('backupReminderDue', () {
    final today = d(2026, 10, 25);

    bool due({
      bool enabled = true,
      DateTime? last,
      DateTime? snoozedUntil,
      int count = 50,
    }) => backupReminderDue(
      enabled: enabled,
      lastBackup: last,
      today: today,
      snoozedUntil: snoozedUntil,
      transactionCount: count,
    );

    test('a recent backup needs no reminder', () {
      expect(due(last: d(2026, 10, 20)), isFalse);
      expect(due(last: d(2026, 9, 25)), isFalse, reason: 'exactly 30 days');
    });

    test('a stale backup does, however few transactions there are', () {
      expect(due(last: d(2026, 9, 24)), isTrue, reason: '31 days');
      expect(due(last: d(2026, 1, 1), count: 1), isTrue);
    });

    test('never backed up: only once there is enough to lose', () {
      expect(due(count: backupRemindAfterTransactions - 1), isFalse);
      expect(due(count: backupRemindAfterTransactions), isTrue);
      expect(due(count: 0), isFalse);
    });

    test('switched off, it never shows', () {
      expect(due(enabled: false, last: d(2020, 1, 1)), isFalse);
      expect(due(enabled: false), isFalse);
    });

    test('"remind me later" is quiet until that day, then comes back', () {
      final stale = d(2026, 1, 1);
      expect(due(last: stale, snoozedUntil: d(2026, 10, 26)), isFalse);
      expect(due(last: stale, snoozedUntil: d(2026, 11, 1)), isFalse);
      expect(
        due(last: stale, snoozedUntil: d(2026, 10, 25)),
        isTrue,
        reason: 'the snooze ends on its day',
      );
      expect(due(last: stale, snoozedUntil: d(2026, 10, 1)), isTrue);
    });

    test('a snooze does not depend on the time of day', () {
      expect(
        backupReminderDue(
          enabled: true,
          lastBackup: d(2026, 1, 1),
          today: DateTime(2026, 10, 25, 23, 59),
          snoozedUntil: DateTime(2026, 10, 26, 0, 0),
          transactionCount: 50,
        ),
        isFalse,
      );
    });

    test('the snooze is a week', () {
      expect(backupSnoozeDays, 7);
    });
  });
}
