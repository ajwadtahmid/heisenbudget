import 'package:drift/drift.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../domain/transaction_type.dart';
import 'app_database.dart';

/// Default categories as (name, icon key), in display order.
const defaultExpenseCategories = <(String, String)>[
  ('Food', 'restaurant'),
  ('Rent', 'home'),
  ('Shopping', 'shopping'),
  ('Medical', 'medical'),
  ('Travel', 'flight'),
  ('Transport', 'bus'),
  ('Bills', 'bills'),
  ('Entertainment', 'movie'),
  (otherCategoryName, defaultCategoryIconKey),
];

const defaultIncomeCategories = <(String, String)>[
  ('Salary', 'salary'),
  ('Freelance', 'freelance'),
  ('Gift', 'gift'),
  (otherCategoryName, defaultCategoryIconKey),
];

/// Inserts the default categories. Called once, from the database's onCreate.
Future<void> seedDefaultCategories(AppDatabase db) async {
  Iterable<CategoriesCompanion> rows(
    TransactionType type,
    List<(String, String)> defaults,
  ) {
    return [
      for (var i = 0; i < defaults.length; i++)
        CategoriesCompanion.insert(
          name: defaults[i].$1,
          type: type,
          icon: Value(defaults[i].$2),
          isDefault: const Value(true),
          isProtected: Value(defaults[i].$1 == otherCategoryName),
          sortOrder: Value(i),
        ),
    ];
  }

  await db.batch((batch) {
    batch.insertAll(db.categories, [
      ...rows(TransactionType.expense, defaultExpenseCategories),
      ...rows(TransactionType.income, defaultIncomeCategories),
    ]);
  });
}
