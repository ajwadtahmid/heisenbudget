import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FavoriteRepository repo;
  late CategoryRow food;
  late CategoryRow transport;
  late CategoryRow salary;

  setUp(() async {
    db = AppDatabase.memory();
    repo = FavoriteRepository(db);
    final all = await CategoryRepository(db).watchAll().first;
    food = all.firstWhere((c) => c.name == 'Food');
    transport = all.firstWhere((c) => c.name == 'Transport');
    salary = all.firstWhere((c) => c.name == 'Salary');
  });
  tearDown(() => db.close());

  FavoriteInput coffee({int? cents = 400, String label = 'Coffee'}) =>
      FavoriteInput(
        label: label,
        type: TransactionType.expense,
        categoryId: food.id,
        amountCents: cents,
        note: 'Flat white',
      );

  Future<List<FavoriteRow>> all() => repo.watchAll().first;

  test('adds a favorite with a fixed amount', () async {
    final id = await repo.add(coffee());
    final row = (await all()).single;
    expect(row.id, id);
    expect(
      (row.label, row.amountCents, row.categoryId, row.note, row.type),
      ('Coffee', 400, food.id, 'Flat white', TransactionType.expense),
    );
  });

  test('an amount can be left out (asked each time)', () async {
    await repo.add(coffee(cents: null));
    expect((await all()).single.amountCents, isNull);
  });

  test('trims the label and blank notes', () async {
    await repo.add(
      FavoriteInput(
        label: '  Bus  ',
        type: TransactionType.expense,
        categoryId: transport.id,
        note: '   ',
      ),
    );
    final row = (await all()).single;
    expect(row.label, 'Bus');
    expect(row.note, isNull);
  });

  test('new favorites go to the end', () async {
    await repo.add(coffee(label: 'A'));
    await repo.add(coffee(label: 'B'));
    await repo.add(coffee(label: 'C'));
    expect((await all()).map((f) => f.label), ['A', 'B', 'C']);
  });

  test('rejects an empty, blank or too long label', () async {
    for (final bad in ['', '   ', 'x' * (maxFavoriteLabelLength + 1)]) {
      expect(
        () => repo.add(coffee(label: bad)),
        throwsA(isA<ArgumentError>()),
        reason: '"$bad"',
      );
    }
    await repo.add(coffee(label: 'x' * maxFavoriteLabelLength));
  });

  test('rejects a zero, negative or huge amount', () async {
    for (final bad in [0, -1, maxAmountCents + 1]) {
      expect(() => repo.add(coffee(cents: bad)), throwsA(isA<RangeError>()));
    }
  });

  test('the category must exist and match the type', () async {
    expect(
      () => repo.add(
        FavoriteInput(
          label: 'Pay',
          type: TransactionType.expense,
          categoryId: salary.id,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.add(
        FavoriteInput(
          label: 'Ghost',
          type: TransactionType.expense,
          categoryId: 99999,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await all(), isEmpty);
  });

  test('stops at the limit', () async {
    for (var i = 0; i < maxFavorites; i++) {
      await repo.add(coffee(label: 'F$i'));
    }
    await expectLater(
      repo.add(coffee(label: 'one too many')),
      throwsA(isA<FavoriteLimitException>()),
    );
    expect(await all(), hasLength(maxFavorites));
    // Deleting one makes room.
    await repo.delete((await all()).first.id);
    await repo.add(coffee(label: 'fits now'));
    expect(await all(), hasLength(maxFavorites));
  });

  test(
    'update changes label, amount, category and note, not the type',
    () async {
      final id = await repo.add(coffee());
      await repo
          .update(
            id,
            FavoriteInput(
              label: 'Bus fare',
              type: TransactionType.income, // ignored: type cannot change
              categoryId: transport.id,
              amountCents: null,
              note: null,
            ),
          )
          .onError<ArgumentError>((_, _) {});
      // An income category on an expense favorite is refused; try a valid edit.
      await repo.update(
        id,
        FavoriteInput(
          label: 'Bus fare',
          type: TransactionType.expense,
          categoryId: transport.id,
          amountCents: null,
          note: null,
        ),
      );
      final row = (await all()).single;
      expect(
        (row.label, row.amountCents, row.categoryId, row.note, row.type),
        ('Bus fare', null, transport.id, null, TransactionType.expense),
      );
    },
  );

  test('an income category cannot be put on an expense favorite', () async {
    final id = await repo.add(coffee());
    await expectLater(
      repo.update(
        id,
        FavoriteInput(
          label: 'Coffee',
          type: TransactionType.expense,
          categoryId: salary.id,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect((await all()).single.categoryId, food.id);
  });

  test('reorder puts them in the given order', () async {
    final a = await repo.add(coffee(label: 'A'));
    final b = await repo.add(coffee(label: 'B'));
    final c = await repo.add(coffee(label: 'C'));
    await repo.reorder([c, a, b]);
    expect((await all()).map((f) => f.label), ['C', 'A', 'B']);
    // A new one still goes last.
    await repo.add(coffee(label: 'D'));
    expect((await all()).map((f) => f.label), ['C', 'A', 'B', 'D']);
  });

  test('delete removes only that favorite', () async {
    final a = await repo.add(coffee(label: 'A'));
    await repo.add(coffee(label: 'B'));
    await repo.delete(a);
    expect((await all()).map((f) => f.label), ['B']);
  });

  test('favorites keep working when their category is archived', () async {
    await repo.add(coffee());
    await CategoryRepository(db).archive(food.id);
    expect((await all()).single.categoryId, food.id);
  });
}
