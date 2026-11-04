import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/database_files.dart';
import '../database/database_opener.dart';
import '../repositories/settings_repository.dart';
import 'backup_data.dart';
import 'backup_service.dart';

/// Replaces an unopened database from Recovery. The original files and
/// preferences remain recoverable until the replacement is open and its
/// settings have been saved. Call [recoverInterrupted] before normal startup.
class RecoveryRestore {
  RecoveryRestore(this.files, this.prefs, this.settings, {required this.open});

  final DatabaseFiles files;
  final SharedPreferences prefs;
  final SettingsRepository settings;
  final DatabaseOpener open;

  static const _suffixes = ['', '-journal', '-wal', '-shm'];

  Directory get _work =>
      Directory('${files.directory.path}/heisenbudget.restore');
  File _file(String name) => File('${_work.path}/$name');
  File get _pending => _file('pending.json');
  File get _committed => _file('committed.json');

  /// Only for an explicitly confirmed erase. Remove saved recovery originals
  /// too, so the next startup cannot resurrect data the user chose to erase.
  Future<void> discard() async {
    await files.deleteRecoveryOriginals();
  }

  /// A pending replacement is rolled back before any database is opened.
  /// Copies, rather than moves, make rollback repeatable if interrupted too.
  /// A committed replacement only needs cleanup; it must not be rolled back.
  Future<void> recoverInterrupted() async {
    if (!await _work.exists()) return;
    if (await _committed.exists()) {
      await _cleanCommitted();
      return;
    }
    if (await _pending.exists()) {
      final journal = jsonDecode(await _pending.readAsString()) as Map;
      final suffixes = (journal['files'] as List).cast<String>();
      if (suffixes.any((s) => !_suffixes.contains(s))) {
        throw const FormatException('Invalid recovery journal.');
      }
      // Check every saved file before touching the live generation.
      for (final suffix in suffixes) {
        if (!await _file('original.sqlite$suffix').exists()) {
          throw const FileSystemException('Recovery original is unavailable.');
        }
      }
      for (final suffix in _suffixes) {
        final live = File('${files.database.path}$suffix');
        if (suffixes.contains(suffix)) {
          await _file('original.sqlite$suffix').copy(live.path);
        } else if (await live.exists()) {
          await live.delete();
        }
      }
      final previous = (journal['preferences'] as Map).cast<String, Object>();
      for (final key in prefs.getKeys().difference(previous.keys.toSet())) {
        await _saved(prefs.remove(key));
      }
      for (final entry in previous.entries) {
        final value = entry.value;
        await _saved(switch (value) {
          bool v => prefs.setBool(entry.key, v),
          int v => prefs.setInt(entry.key, v),
          double v => prefs.setDouble(entry.key, v),
          String v => prefs.setString(entry.key, v),
          List v => prefs.setStringList(entry.key, v.cast<String>()),
          _ => throw const FormatException('Invalid recovery preferences.'),
        });
      }
      // Rollback is complete. Mark it before cleanup so partial directory
      // deletion cannot leave a pending journal with missing originals.
      await _pending.rename(_committed.path);
    }
    await _cleanCommitted();
  }

  Future<AppDatabase> restore(BackupData data) async {
    await recoverInterrupted();
    // A failed cleanup must not let a new operation overwrite its journal.
    if (await _work.exists()) {
      throw const FileSystemException('Recovery cleanup could not finish.');
    }
    await _work.create();
    AppDatabase? db;
    try {
      final staged = _file('replacement.sqlite');
      db = open(staged);
      await BackupService(db, settings).restoreDatabase(data);
      final integrity = await db.customSelect('PRAGMA integrity_check').get();
      final references = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      if (integrity.length != 1 ||
          integrity.single.data.values.single != 'ok' ||
          references.isNotEmpty) {
        throw const FormatException('The restored database failed validation.');
      }
      // The installed file must not depend on sidecars in the staging folder.
      final mode = await db
          .customSelect('PRAGMA journal_mode = DELETE')
          .getSingle();
      if (mode.data.values.single != 'delete') {
        throw const FileSystemException('The restored database is still busy.');
      }
      await db.close();
      db = null;

      final originals = <String>[];
      for (final suffix in _suffixes) {
        final source = File('${files.database.path}$suffix');
        if (await source.exists()) {
          await source.copy(_file('original.sqlite$suffix').path);
          originals.add(suffix);
        }
      }
      final metadata = _file('preparing.json');
      await metadata.writeAsString(
        jsonEncode({
          'files': originals,
          'preferences': {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          },
        }),
        flush: true,
      );
      // Only this atomic rename permits touching the original generation.
      await metadata.rename(_pending.path);
      await files.deleteDatabase();
      await staged.rename(files.database.path);
      db = open(files.database);
      await db.customSelect('SELECT 1').get();
      await settings.applyBackup(data.settings);
      await _saved(prefs.setInt(schemaVersionPrefKey, currentSchemaVersion));
      await _pending.rename(_committed.path);
      final ready = db;
      db = null;
      await _cleanCommitted();
      return ready;
    } catch (_) {
      await db?.close();
      await recoverInterrupted();
      rethrow;
    }
  }

  Future<void> _cleanCommitted() async {
    try {
      // Remove the commit marker last. A failed recursive deletion must not
      // cause the remaining originals to be interpreted as a pending restore.
      await for (final entity in _work.list()) {
        if (entity.path != _committed.path) {
          await entity.delete(recursive: true);
        }
      }
      if (await _committed.exists()) await _committed.delete();
      await _work.delete();
    } on FileSystemException {
      // Retry on startup; a committed replacement remains valid.
    }
  }

  Future<void> _saved(Future<bool> write) async {
    if (!await write) {
      throw const FileSystemException('Settings could not be saved.');
    }
  }
}
