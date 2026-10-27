import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'data/backup/backup_data.dart';
import 'data/backup/backup_service.dart';
import 'data/backup/file_exchange.dart';
import 'data/database/app_database.dart';
import 'data/database/database_files.dart';
import 'data/database/database_opener.dart';
import 'data/repositories/settings_repository.dart';
import 'features/recovery/recovery_screen.dart';
import 'providers/backup_providers.dart';
import 'providers/database_providers.dart';
import 'providers/settings_providers.dart';

/// Opens the database before the app starts. If that works, the app runs; if
/// it does not (a failed update, a damaged file), the recovery screen offers
/// a way out instead of a broken app.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.prefs,
    this.locate = DatabaseFiles.locate,
    this.openDatabase = AppDatabase.open,
    this.exchange = const FileExchange(),
    this.now,
  });

  final SharedPreferences prefs;

  /// Where the database lives. Tests point it at a temporary folder.
  final Future<DatabaseFiles> Function() locate;
  final DatabaseOpener openDatabase;
  final FileExchange exchange;
  final DateTime Function()? now;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

/// The outcome of one try at opening the data.
class _Boot {
  const _Boot.ready(AppDatabase this.db, this.files)
    : error = null,
      copyMadeAt = null;

  const _Boot.failed(
    DatabaseOpenException this.error,
    this.files,
    this.copyMadeAt,
  ) : db = null;

  final AppDatabase? db;
  final DatabaseOpenException? error;
  final DatabaseFiles files;
  final DateTime? copyMadeAt;
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<_Boot> _boot = _start();
  AppDatabase? _db;

  SettingsRepository get _settings => SettingsRepository(
    widget.prefs,
    defaultCurrency: defaultCurrencyCodeFor(
      ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    ),
  );

  Future<_Boot> _start() async {
    final files = await widget.locate();
    try {
      final db = await openAppDatabase(
        prefs: widget.prefs,
        files: files,
        open: widget.openDatabase,
        now: widget.now,
      );
      _db = db;
      return _Boot.ready(db, files);
    } on DatabaseOpenException catch (e) {
      DateTime? made;
      try {
        made = await files.copyMadeAt();
      } catch (_) {}
      return _Boot.failed(e, files, made);
    }
  }

  void _again() {
    setState(() {
      _boot = _start();
    });
  }

  Future<void> _restoreCopy(DatabaseFiles files) async {
    final version = await files.restoreCopy();
    await widget.prefs.setInt(schemaVersionPrefKey, version);
    _again();
  }

  Future<void> _erase(DatabaseFiles files) async {
    await files.deleteDatabase();
    await files.deleteCopies();
    await widget.prefs.clear();
    _again();
  }

  Future<void> _restoreBackup(DatabaseFiles files, BackupData data) async {
    // The file was read and checked first; only now is the old data replaced.
    await files.deleteDatabase();
    await widget.prefs.remove(schemaVersionPrefKey);
    final db = await openAppDatabase(
      prefs: widget.prefs,
      files: files,
      open: widget.openDatabase,
      now: widget.now,
    );
    try {
      await BackupService(db, _settings, files: files).restore(data);
    } catch (_) {
      await db.close();
      rethrow;
    }
    _db = db;
    if (mounted) {
      setState(() {
        _boot = Future.value(_Boot.ready(db, files));
      });
    }
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _boot,
      builder: (context, snapshot) {
        final boot = snapshot.data;
        if (boot == null) return const _Blank();
        final db = boot.db;
        if (db != null) {
          return ProviderScope(
            key: ObjectKey(db),
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              sharedPreferencesProvider.overrideWithValue(widget.prefs),
              databaseFilesProvider.overrideWithValue(boot.files),
              fileExchangeProvider.overrideWithValue(widget.exchange),
            ],
            child: const HeisenbudgetApp(),
          );
        }
        final look = _settings.load();
        return MaterialApp(
          title: appName,
          theme: lightTheme(accent: look.accent, font: look.textFont),
          darkTheme: darkTheme(accent: look.accent, font: look.textFont),
          themeMode: look.themeMode,
          home: RecoveryScreen(
            error: boot.error!,
            copyMadeAt: boot.copyMadeAt,
            pickBackup: widget.exchange.pickFile,
            onRetry: () async => _again(),
            onRestoreCopy: () => _restoreCopy(boot.files),
            onRestoreBackup: (data) => _restoreBackup(boot.files, data),
            onErase: () => _erase(boot.files),
          ),
        );
      },
    );
  }
}

/// The instant before the data is open: the launch colour, so nothing flashes.
class _Blank extends StatelessWidget {
  const _Blank();

  @override
  Widget build(BuildContext context) {
    final dark =
        ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF070A09) : const Color(0xFFF4F6F5),
      child: const SizedBox.expand(),
    );
  }
}
