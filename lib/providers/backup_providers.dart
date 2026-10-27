import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_service.dart';
import '../data/backup/file_exchange.dart';
import 'database_providers.dart';
import 'settings_providers.dart';

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
