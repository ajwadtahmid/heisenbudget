import 'package:drift/drift.dart' show OrderingTerm;

import '../database/app_database.dart';
import '../repositories/settings_repository.dart';
import 'backup_data.dart';

/// Reads everything the app stores into a [BackupData] and puts one back.
class BackupService {
  BackupService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// A consistent copy of all categories, transactions and portable settings.
  Future<BackupData> snapshot({required DateTime now}) {
    return _db.transaction(() async {
      final categories = await (_db.select(
        _db.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
      final transactions = await (_db.select(
        _db.transactions,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      return BackupData(
        exportedAt: now,
        settings: _settings.toBackup(),
        categories: categories,
        transactions: transactions,
      );
    });
  }

  /// Replaces all categories and transactions with [data], then applies its
  /// settings. The database part is one transaction: if anything fails, the
  /// existing data is left exactly as it was.
  Future<void> restore(BackupData data) async {
    await _db.transaction(() async {
      // Transactions first: they reference categories.
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.categories).go();
      await _db.batch((batch) {
        batch.insertAll(_db.categories, data.categories);
        batch.insertAll(_db.transactions, data.transactions);
      });
    });
    await _settings.applyBackup(data.settings);
  }
}
