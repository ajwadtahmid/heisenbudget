import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/domain/week_mode.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsRepository> makeRepo([
  Map<String, Object> initial = const {},
  String defaultCurrency = 'USD',
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return SettingsRepository(prefs, defaultCurrency: defaultCurrency);
}

void main() {
  group('SettingsRepository', () {
    test('returns the documented defaults', () async {
      final s = (await makeRepo()).load();
      expect(s.currency.code, 'USD');
      expect(s.currencySymbol, r'$');
      expect(s.weekMode, WeekMode.calendar);
      expect(s.weekStartDay, 1);
      expect(s.lastExpenseCategoryId, isNull);
      expect(s.lastIncomeCategoryId, isNull);
    });

    test('the default currency can come from the device locale', () async {
      final s = (await makeRepo(const {}, 'BDT')).load();
      expect(s.currency.code, 'BDT');
      expect(s.currencySymbol, '৳');
    });

    test('persists every setting', () async {
      final repo = await makeRepo();
      await repo.setCurrencyCode('BDT');
      await repo.setWeekMode(WeekMode.fixed);
      await repo.setWeekStartDay(7);
      await repo.setLastCategory(TransactionType.expense, 4);
      await repo.setLastCategory(TransactionType.income, 11);

      final s = repo.load();
      expect(s.currency.code, 'BDT');
      expect(s.weekMode, WeekMode.fixed);
      expect(s.weekStartDay, 7);
      expect(s.lastCategoryFor(TransactionType.expense), 4);
      expect(s.lastCategoryFor(TransactionType.income), 11);
    });

    test('reads values saved earlier (survives restart)', () async {
      final repo = await makeRepo({
        'currency_code': 'GBP',
        'week_mode': 'fixed',
        'week_start_day': 3,
        'last_category_expense': 2,
      });
      final s = repo.load();
      expect(s.currencySymbol, '£');
      expect(s.weekMode, WeekMode.fixed);
      expect(s.weekStartDay, 3);
      expect(s.lastExpenseCategoryId, 2);
    });

    test('a saved choice beats the locale default', () async {
      final repo = await makeRepo({'currency_code': 'EUR'}, 'BDT');
      expect(repo.load().currency.code, 'EUR');
    });

    test('an unknown stored currency falls back to the default', () async {
      final repo = await makeRepo({'currency_code': 'XXX'}, 'BDT');
      expect(repo.load().currency.code, 'BDT');
    });

    test('out-of-range stored week start day is clamped', () async {
      final repo = await makeRepo({'week_start_day': 99});
      expect(repo.load().weekStartDay, 7);
    });

    test('rejects an unknown currency and bad week days', () async {
      final repo = await makeRepo();
      expect(() => repo.setCurrencyCode('NOPE'), throwsArgumentError);
      expect(() => repo.setWeekStartDay(0), throwsRangeError);
      expect(() => repo.setWeekStartDay(8), throwsRangeError);
    });
  });

  group('defaultCurrencyCodeFor', () {
    test('uses the locale when the currency is known', () {
      expect(defaultCurrencyCodeFor('en-US'), 'USD');
      expect(defaultCurrencyCodeFor('de-DE'), 'EUR');
      expect(defaultCurrencyCodeFor('bn-BD'), 'BDT');
      expect(defaultCurrencyCodeFor('en-GB'), 'GBP');
    });

    test('falls back to USD for nonsense', () {
      expect(defaultCurrencyCodeFor('not a locale!!'), 'USD');
    });
  });

  group('SettingsNotifier', () {
    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('setters save and publish new state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setWeekMode(WeekMode.fixed);
      await notifier.setCurrencyCode('BDT');
      await notifier.setLastCategory(TransactionType.expense, 3);

      final s = container.read(settingsProvider);
      expect(s.weekMode, WeekMode.fixed);
      expect(s.currencySymbol, '৳');
      expect(s.lastExpenseCategoryId, 3);

      // A fresh container over the same prefs sees the saved values.
      final prefs = container.read(sharedPreferencesProvider);
      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);
      expect(second.read(settingsProvider).weekMode, WeekMode.fixed);
      expect(second.read(settingsProvider).currency.code, 'BDT');
    });
  });
}
