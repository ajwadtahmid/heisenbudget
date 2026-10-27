import 'package:drift/drift.dart' show OrderingTerm;

import '../database/app_database.dart';
import '../database/database_files.dart';
import '../database/seed.dart';
import '../repositories/settings_repository.dart';
import 'backup_data.dart';

/// Reads everything the app stores into a [BackupData] and puts one back.
class BackupService {
  BackupService(this._db, this._settings, {this._files});

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// Where the pre-update safety copy is kept, if the app has one.
  final DatabaseFiles? _files;

  /// A consistent copy of all categories, transactions and portable settings.
  Future<BackupData> snapshot({required DateTime now}) {
    return _db.transaction(() async {
      final categories = await (_db.select(
        _db.categories,
      )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
      final rules = await (_db.select(
        _db.recurringRules,
      )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
      final favorites = await (_db.select(
        _db.favorites,
      )..orderBy([(f) => OrderingTerm.asc(f.id)])).get();
      final limits = await (_db.select(
        _db.budgetLimits,
      )..orderBy([(b) => OrderingTerm.asc(b.id)])).get();
      final transactions = await (_db.select(
        _db.transactions,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      return BackupData(
        exportedAt: now,
        settings: _settings.toBackup(),
        categories: categories,
        recurringRules: rules,
        favorites: favorites,
        budgetLimits: limits,
        transactions: transactions,
      );
    });
  }

  /// Replaces all categories and transactions with [data], then applies its
  /// settings. The database part is one transaction: if anything fails, the
  /// existing data is left exactly as it was. If only the settings step fails
  /// afterwards, a [BackupFormatException] says the data was restored.
  Future<void> restore(BackupData data) async {
    await _db.transaction(() async {
      // Out in the order that respects references: transactions, then the
      // rules and favorites that point at categories, then the categories.
      // In is the reverse.
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.favorites).go();
      await _db.delete(_db.recurringRules).go();
      await _db.delete(_db.budgetLimits).go();
      await _db.delete(_db.categories).go();
      await _db.batch((batch) {
        batch.insertAll(_db.categories, data.categories);
        batch.insertAll(_db.recurringRules, data.recurringRules);
        batch.insertAll(_db.favorites, data.favorites);
        batch.insertAll(_db.budgetLimits, data.budgetLimits);
        batch.insertAll(_db.transactions, data.transactions);
      });
    });
    try {
      await _settings.applyBackup(data.settings);
    } catch (_) {
      // The data is already replaced, so say that rather than "nothing changed".
      throw const BackupFormatException(
        'Your data was restored, but some settings could not be saved. '
        'Check Appearance and Money & dates.',
      );
    }
  }

  /// Wipes everything: transactions, repeating rules, favorites, every
  /// category, then puts the default categories back, and forgets all
  /// settings. The database part is one transaction.
  Future<void> eraseEverything() async {
    await _db.transaction(() async {
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.favorites).go();
      await _db.delete(_db.recurringRules).go();
      await _db.delete(_db.budgetLimits).go();
      await _db.delete(_db.categories).go();
      await seedDefaultCategories(_db);
    });
    await _settings.clearAll();
    // The safety copy holds the same financial data, so it goes too.
    await _files?.deleteCopies();
  }
}
