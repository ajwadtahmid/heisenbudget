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
}
