import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/design/app_colors.dart';
import 'package:heisenbudget/core/design/app_font.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/providers/category_providers.dart';
import 'package:heisenbudget/providers/database_providers.dart';
import 'package:heisenbudget/providers/period_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:heisenbudget/providers/transaction_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late AppDatabase db;
  late TransactionRepository txs;
  late Map<String, int> ids; // category name (expense) -> id
  late int salary;

  Future<void> add(
    int cents,
    DateTime date, {
    String category = 'Food',
    TransactionType type = TransactionType.expense,
  }) async {
    final categoryId = type == TransactionType.income ? salary : ids[category]!;
    await txs.add(
      TransactionInput(
        amountCents: cents,
        type: type,
        date: date,
        categoryId: categoryId,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase.memory();
    txs = TransactionRepository(db);
    final all = await db.select(db.categories).get();
    ids = {
      for (final c in all)
        if (c.type == TransactionType.expense) c.name: c.id,
    };
    salary = all
        .firstWhere(
          (c) => c.name == 'Salary' && c.type == TransactionType.income,
        )
        .id;
  });

  tearDown(() => db.close());

  group('watchSpendByCategory', () {
    final october = monthOf(2026, 10);

    test('sums expenses per category, biggest first', () async {
      await add(1000, d(2026, 10, 1), category: 'Food');
      await add(2500, d(2026, 10, 2), category: 'Food');
      await add(9000, d(2026, 10, 3), category: 'Rent');
      await add(500, d(2026, 10, 4), category: 'Travel');

      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend.map((s) => s.name), ['Rent', 'Food', 'Travel']);
      expect(spend.map((s) => s.cents), [9000, 3500, 500]);
    });

    test('carries the category icon', () async {
      await add(100, d(2026, 10, 1), category: 'Food');
      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend.single.icon, 'restaurant');
    });

    test('ignores income and other periods', () async {
      await add(7000, d(2026, 10, 1), type: TransactionType.income);
      await add(300, d(2026, 9, 30), category: 'Food'); // before
      await add(400, d(2026, 11, 1), category: 'Food'); // after
      await add(150, d(2026, 10, 1), category: 'Food'); // first day: counted
      await add(250, d(2026, 10, 31), category: 'Food'); // last day: counted

      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend, hasLength(1));
      expect(spend.single.cents, 400);
    });

    test('ties are ordered by name', () async {
      await add(500, d(2026, 10, 1), category: 'Travel');
      await add(500, d(2026, 10, 2), category: 'Bills');
      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend.map((s) => s.name), ['Bills', 'Travel']);
    });

    test('an empty period is an empty list', () async {
      expect(await txs.watchSpendByCategory(october).first, isEmpty);
    });

    test('archived categories still count', () async {
      await add(800, d(2026, 10, 1), category: 'Travel');
      await db.customStatement(
        "UPDATE categories SET is_archived = 1 WHERE name = 'Travel'",
      );
      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend.single.name, 'Travel');
    });

    test('updates when a transaction is added', () async {
      final seen = <int>[];
      final sub = txs
          .watchSpendByCategory(october)
          .listen((s) => seen.add(s.fold(0, (sum, e) => sum + e.cents)));
      addTearDown(sub.cancel);
      await settle();
      await add(1200, d(2026, 10, 5));
      await settle();
      expect(seen.first, 0);
      expect(seen.last, 1200);
    });

    test('handles the largest amounts', () async {
      await add(99999999999, d(2026, 10, 1), category: 'Rent');
      await add(99999999999, d(2026, 10, 2), category: 'Rent');
      final spend = await txs.watchSpendByCategory(october).first;
      expect(spend.single.cents, 199999999998);
    });
  });

  group('hasAny', () {
    test(
      'false on a fresh database, true after the first transaction',
      () async {
        expect(await txs.hasAny(), isFalse);
        await add(100, d(2026, 10, 1));
        expect(await txs.hasAny(), isTrue);
      },
    );
  });

  group('settings: new preferences', () {
    Future<SettingsRepository> repo([
      Map<String, Object> initial = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initial);
      return SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
    }

    test('defaults', () async {
      final s = (await repo()).load();
      expect(s.accent, AccentColor.assay);
      expect(s.textFont, AppFont.geist);
      expect(s.labFlavor, isTrue);
      expect(s.openingBalanceCents, 0);
      expect(s.onboardingDone, isFalse);
    });

    test('every new setting round-trips', () async {
      final r = await repo();
      await r.setAccent(AccentColor.violet);
      await r.setTextFont(AppFont.atkinson);
      await r.setLabFlavor(false);
      await r.setOpeningBalanceCents(-12345);
      await r.setOnboardingDone(true);
      final s = r.load();
      expect(s.accent, AccentColor.violet);
      expect(s.textFont, AppFont.atkinson);
      expect(s.labFlavor, isFalse);
      expect(s.openingBalanceCents, -12345);
      expect(s.onboardingDone, isTrue);
    });

    test('unknown saved names fall back to the defaults', () async {
      final s = (await repo({'accent': 'chartreuse', 'text_font': 'wingdings'}))
          .load();
      expect(s.accent, AccentColor.assay);
      expect(s.textFont, AppFont.geist);
    });
  });

  group('providers', () {
    late ProviderContainer container;
    late SharedPreferences prefs;

    Future<void> start([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          nowProvider.overrideWithValue(() => d(2026, 10, 15)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(allCategoriesProvider, (_, _) {});
    }

    void keep(ProviderListenable<Object?> p) => container.listen(p, (_, _) {});

    test('the opening balance counts toward the balance', () async {
      await start({'opening_balance_cents': 50000});
      keep(balanceProvider);
      await add(2000, d(2026, 10, 1), type: TransactionType.income);
      await add(500, d(2026, 10, 2));
      await settle();
      expect(container.read(balanceProvider).value, 51500);
    });

    test('a negative opening balance works', () async {
      await start({'opening_balance_cents': -10000});
      keep(balanceProvider);
      await add(2500, d(2026, 10, 1), type: TransactionType.income);
      await settle();
      expect(container.read(balanceProvider).value, -7500);
    });

    test('the opening balance never counts as Received', () async {
      await start({'opening_balance_cents': 50000});
      keep(periodSummaryProvider);
      await add(2000, d(2026, 10, 1), type: TransactionType.income);
      await settle();
      final summary = container.read(periodSummaryProvider).value!;
      expect(summary.receivedCents, 2000);
      expect(summary.netCents, 2000);
    });

    test('changing the opening balance updates the balance', () async {
      await start();
      keep(balanceProvider);
      await add(1000, d(2026, 10, 1), type: TransactionType.income);
      await settle();
      expect(container.read(balanceProvider).value, 1000);

      await container
          .read(settingsProvider.notifier)
          .setOpeningBalanceCents(9000);
      await settle();
      expect(container.read(balanceProvider).value, 10000);
    });

    test('spendByCategoryProvider follows the selected period', () async {
      await start();
      keep(spendByCategoryProvider);
      await add(500, d(2026, 10, 3), category: 'Food');
      await add(900, d(2026, 11, 3), category: 'Rent');
      await settle();
      expect(
        container.read(spendByCategoryProvider).value!.single.name,
        'Food',
      );

      container.read(selectedPeriodProvider.notifier).step(1);
      await settle();
      expect(
        container.read(spendByCategoryProvider).value!.single.name,
        'Rent',
      );
    });

    test('copyProvider follows the Lab flavor setting', () async {
      await start();
      expect(container.read(copyProvider).lab, isTrue);
      await container.read(settingsProvider.notifier).setLabFlavor(false);
      expect(container.read(copyProvider).lab, isFalse);
    });

    group('needsWelcomeProvider', () {
      test('true on a fresh install', () async {
        await start();
        expect(await container.read(needsWelcomeProvider.future), isTrue);
      });

      test('false once the tour has been done', () async {
        await start({'onboarding_done': true});
        expect(await container.read(needsWelcomeProvider.future), isFalse);
      });

      test('false, and remembered, when data already exists', () async {
        await start();
        await add(100, d(2026, 10, 1));
        expect(await container.read(needsWelcomeProvider.future), isFalse);
        await settle();
        expect(prefs.getBool('onboarding_done'), isTrue);
      });
    });
  });
}
