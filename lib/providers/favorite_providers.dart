import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/favorite_repository.dart';
import 'database_providers.dart';

final favoriteRepositoryProvider = Provider<FavoriteRepository>(
  (ref) => FavoriteRepository(ref.watch(appDatabaseProvider)),
);

/// The favorites in strip order.
final favoritesProvider = StreamProvider<List<FavoriteRow>>((ref) {
  return ref.watch(favoriteRepositoryProvider).watchAll();
});
