import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/transaction_type.dart';
import 'database_providers.dart';

/// Non-archived categories of one type: what pickers show.
final activeCategoriesProvider =
    StreamProvider.family<List<CategoryRow>, TransactionType>((ref, type) {
      return ref.watch(categoryRepositoryProvider).watchActive(type);
    });

/// Every category including archived ones: for the manager and for showing
/// the category of old transactions.
final allCategoriesProvider = StreamProvider<List<CategoryRow>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll();
});
