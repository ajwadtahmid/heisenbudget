import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The unopened live database and its pre-upgrade safety copy. Complete copy
/// generations are published by directory rename; older flat copies still work.
class DatabaseFiles {
  const DatabaseFiles(this.directory);

  static Future<DatabaseFiles> locate() async =>
      DatabaseFiles(await getApplicationDocumentsDirectory());

  static const copyKeepDays = 14;
  static const _sideFiles = ['-journal', '-wal', '-shm'];
  static const _suffixes = ['', ..._sideFiles];
  static final _legacyName = RegExp(r'^heisenbudget\.before-v(\d+)\.sqlite$');
  static final _generationName = RegExp(
    r'^heisenbudget\.before-v(\d+)\.(\d+)\.copy$',
  );
  final Directory directory;

  File get database => File('${directory.path}/heisenbudget.sqlite');
  Directory get _restore =>
      Directory('${directory.path}/heisenbudget.copy-restore');
  File _restoreFile(String name) => File('${_restore.path}/$name');
  Future<bool> get databaseExists => database.exists();

  Future<int?> schemaVersion() async {
    if (!await database.exists()) return null;
    return _inspect(database);
  }

  int _inspect(File file, {bool validate = false}) {
    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    try {
      if (validate) {
        final check = db.select('PRAGMA quick_check');
        if (check.length != 1 || check.single.values.single != 'ok') {
          throw const FormatException('The safety copy failed validation.');
        }
      }
      return db.select('PRAGMA user_version').single.values.single as int;
    } finally {
      db.close();
    }
  }

  Future<({int version, File file, int generation})?> _latest() async {
    if (!await directory.exists()) return null;
    ({int version, File file, int generation})? latest;
    await for (final entry in directory.list()) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      final generation = _generationName.firstMatch(name);
      final legacy = _legacyName.firstMatch(name);
      final candidate = generation != null && entry is Directory
          ? (
              version: int.parse(generation[1]!),
              file: File('${entry.path}/heisenbudget.sqlite'),
              generation: int.parse(generation[2]!),
            )
          : legacy != null && entry is File
          ? (version: int.parse(legacy[1]!), file: entry, generation: 0)
          : null;
      if (candidate != null &&
          (latest == null || candidate.generation > latest.generation)) {
        latest = candidate;
      }
    }
    return latest;
  }

  /// Current completed copy, including legacy installations. Never a partial one.
  Future<File?> get safetyCopy async => (await _latest())?.file;
  Future<int?> copyVersion() async => (await _latest())?.version;
  Future<DateTime?> copyMadeAt() async => (await safetyCopy)?.lastModified();

  Future<void> _copyFiles(File source, File target) async {
    for (final suffix in _suffixes) {
      final part = File('${source.path}$suffix');
      if (await part.exists()) await part.copy('${target.path}$suffix');
    }
  }

  Future<void> copyBeforeUpgrade(int version) async {
    final previous = await _latest();
    final staging = await directory.createTemp('heisenbudget.copy-staging-');
    try {
      final staged = File('${staging.path}/heisenbudget.sqlite');
      await _copyFiles(database, staged);
      _inspect(staged, validate: true);
      final clock = DateTime.now().microsecondsSinceEpoch;
      final generation = clock > (previous?.generation ?? 0)
          ? clock
          : previous!.generation + 1;
      final published =
          '${directory.path}/heisenbudget.before-v$version.$generation.copy';
      await staging.rename(published);
      // Only remove the previous copy after the complete generation is visible.
      try {
        await _deleteCopiesExcept(published);
      } on FileSystemException {
        // Old copies are still erased/pruned later; the newest is unambiguous.
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Restores a checked copy while retaining the original through installation.
  /// Startup repeats rollback if a process stops between file operations.
  Future<int> restoreCopy() async {
    await recoverInterruptedRestore();
    final copy = await _latest();
    if (copy == null) throw StateError('There is no copy to restore.');
    await _restore.create();
    try {
      final staged = _restoreFile('replacement.sqlite');
      await _copyFiles(copy.file, staged);
      if (_inspect(staged, validate: true) != copy.version) {
        throw const FormatException('The safety copy schema does not match.');
      }
      final originals = <String>[];
      for (final suffix in _suffixes) {
        final part = File('${database.path}$suffix');
        if (await part.exists()) {
          await part.copy(_restoreFile('original.sqlite$suffix').path);
          originals.add(suffix);
        }
      }
      final metadata = _restoreFile('preparing.json');
      await metadata.writeAsString(jsonEncode(originals), flush: true);
      await metadata.rename(_restoreFile('pending.json').path);
      await deleteDatabase();
      await _copyFiles(staged, database);
      _inspect(database, validate: true);
      await _restoreFile('pending.json').rename(_restoreFile('done').path);
      await _cleanRestore();
      return copy.version;
    } catch (_) {
      await recoverInterruptedRestore();
      rethrow;
    }
  }

  Future<void> recoverInterruptedRestore() async {
    if (!await _restore.exists()) return;
    final pending = _restoreFile('pending.json');
    if (await pending.exists()) {
      final originals = (jsonDecode(await pending.readAsString()) as List)
          .cast<String>();
      if (originals.any((s) => !_suffixes.contains(s))) {
        throw const FormatException('Invalid safety-copy restore journal.');
      }
      for (final suffix in originals) {
        if (!await _restoreFile('original.sqlite$suffix').exists()) {
          throw const FileSystemException('Original database is unavailable.');
        }
      }
      for (final suffix in _suffixes) {
        final target = File('${database.path}$suffix');
        if (originals.contains(suffix)) {
          await _restoreFile('original.sqlite$suffix').copy(target.path);
        } else if (await target.exists()) {
          await target.delete();
        }
      }
      await pending.rename(_restoreFile('done').path);
    }
    await _cleanRestore();
    if (await _restore.exists()) {
      throw const FileSystemException(
        'Safety-copy restore cleanup is incomplete.',
      );
    }
  }

  Future<void> _cleanRestore() async {
    try {
      await for (final entry in _restore.list()) {
        if (entry.path != _restoreFile('done').path) {
          await entry.delete(recursive: true);
        }
      }
      if (await _restoreFile('done').exists()) {
        await _restoreFile('done').delete();
      }
      await _restore.delete();
    } on FileSystemException {
      // The done marker stays until originals are gone. Startup retries cleanup.
    }
  }

  Future<void> deleteDatabase() async {
    for (final suffix in _suffixes) {
      final file = File('${database.path}$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _deleteCopiesExcept(String? keep) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (entry.path != keep &&
          (name.startsWith('heisenbudget.before-v') ||
              name.startsWith('heisenbudget.copy-staging-'))) {
        await entry.delete(recursive: true);
      }
    }
  }

  Future<void> deleteCopies() async {
    // Explicit erase must not allow a pending rollback to resurrect old data.
    if (await _restore.exists()) await _restore.delete(recursive: true);
    await _deleteCopiesExcept(null);
  }

  Future<void> pruneCopies(DateTime now) async {
    final made = await copyMadeAt();
    if (made != null && now.difference(made).inDays >= copyKeepDays) {
      await deleteCopies();
    }
  }
}
