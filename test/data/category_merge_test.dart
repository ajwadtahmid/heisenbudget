import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  late AppDatabase db;
  late CategoryRepository cats;
  late TransactionRepository txs;
  late BudgetRepository budgets;
  late CategoryRow food;
  late CategoryRow rent;
  late CategoryRow other;
  late CategoryRow salary;

  setUp(() async {
    db = AppDatabase.memory();
    cats = CategoryRepository(db);
    txs = TransactionRepository(db);
    budgets = BudgetRepository(db);
    final all = await cats.watchAll().first;
    CategoryRow find(String name, TransactionType type) =>
        all.firstWhere((c) => c.name == name && c.type == type);
    food = find('Food', TransactionType.expense);
    rent = find('Rent', TransactionType.expense);
    other = all.firstWhere(
      (c) => c.isProtected && c.type == TransactionType.expense,
    );
    salary = find('Salary', TransactionType.income);
  });

  tearDown(() => db.close());

  Future<void> spend(int cents, CategoryRow category) => txs.add(
    TransactionInput(
      amountCents: cents,
      type: TransactionType.expense,
      date: d(2026, 10, 5),
      categoryId: category.id,
    ),
  );

  Future<void> limit(CategoryRow category, int cents) => budgets.setLimit(
    start: d(2026, 10, 1),
    unit: BudgetUnit.month,
    categoryId: category.id,
    amountCents: cents,
    today: d(2026, 10, 15),
  );

  test(
    'moves transactions, rules and favorites and archives the source',
    () async {
      await spend(500, food);
      await spend(700, food);
      await spend(900, rent);
      await FavoriteRepository(db).add(
        FavoriteInput(
          label: 'Lunch',
          type: TransactionType.expense,
          amountCents: 800,
          categoryId: food.id,
        ),
      );

      final moved = await cats.merge(fromId: food.id, intoId: rent.id);

      expect(moved, 2);
      final rows = await txs.watchFiltered().first;
      expect(rows.every((t) => t.transaction.categoryId == rent.id), isTrue);
      final favorites = await db.select(db.favorites).get();
      expect(favorites.single.categoryId, rent.id);
      expect((await cats.getById(food.id))!.isArchived, isTrue);
      expect((await cats.getById(rent.id))!.isArchived, isFalse);
    },
  );

  test('a budget limit moves when the target has none', () async {
    await limit(food, 20000);
    await cats.merge(fromId: food.id, intoId: rent.id);

    final rows = await db.select(db.budgetLimits).get();
    expect(rows.single.categoryId, rent.id);
    expect(rows.single.amountCents, 20000);
  });

  test('the source limit is dropped when the target already has one', () async {
    await limit(food, 20000);
    await limit(rent, 90000);
    await cats.merge(fromId: food.id, intoId: rent.id);

    final rows = await db.select(db.budgetLimits).get();
    expect(rows.single.categoryId, rent.id);
    expect(rows.single.amountCents, 90000);
  });

  test('refuses Other, another type, itself and an archived target', () async {
    expect(
      () => cats.merge(fromId: other.id, intoId: food.id),
      throwsA(isA<ProtectedCategoryException>()),
    );
    expect(
      () => cats.merge(fromId: food.id, intoId: salary.id),
      throwsArgumentError,
    );
    expect(
      () => cats.merge(fromId: food.id, intoId: food.id),
      throwsArgumentError,
    );
    await cats.archive(rent.id);
    expect(
      () => cats.merge(fromId: food.id, intoId: rent.id),
      throwsArgumentError,
    );
  });

  test('a refused merge leaves everything as it was', () async {
    await spend(500, food);
    await expectLater(
      cats.merge(fromId: food.id, intoId: salary.id),
      throwsArgumentError,
    );
    final rows = await txs.watchFiltered().first;
    expect(rows.single.transaction.categoryId, food.id);
    expect((await cats.getById(food.id))!.isArchived, isFalse);
  });
}
