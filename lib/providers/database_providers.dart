import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/csv_importer.dart';
import '../data/database/app_database.dart';
import '../data/database/database_files.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';

/// The single database for the whole app. It is opened (and upgraded) before
/// the app starts, by the start-up check, which overrides this provider; tests
/// override it with an in-memory one.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('The database is opened before the app starts.'),
);

/// Where the database and its safety copy live. Set at start-up; null in tests,
/// which have no files.
final databaseFilesProvider = Provider<DatabaseFiles?>((ref) => null);

/// Invalidates temporary UI state that refers to IDs from replaced data.
final ledgerRevisionProvider = NotifierProvider<LedgerRevision, int>(
  LedgerRevision.new,
);

class LedgerRevision extends Notifier<int> {
  @override
  int build() => 0;
  void replaced() => state++;
}

/// Adds the rows of a CSV file in one transaction.
final csvImporterProvider = Provider<CsvImporter>(
  (ref) => CsvImporter(ref.watch(appDatabaseProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);
