import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/domain/saved_filter.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/domain/week_mode.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';

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

  group('the favorite launcher shortcut setting', () {
    Future<SettingsRepository> repo([
      Map<String, Object> values = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(values);
      return SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
    }

    test('is on by default, and can be turned off and on', () async {
      final r = await repo();
      expect(r.load().favoriteShortcut, isTrue);
      await r.setFavoriteShortcut(false);
      expect(r.load().favoriteShortcut, isFalse);
      await r.setFavoriteShortcut(true);
      expect(r.load().favoriteShortcut, isTrue);
    });

    test('travels in a backup, and an older backup leaves it alone', () async {
      final r = await repo({'favorite_shortcut': false});
      final saved = r.toBackup();
      expect(saved.favoriteShortcut, isFalse);
      expect(saved.toJson()['favoriteShortcut'], isFalse);

      final other = await repo();
      await other.applyBackup(BackupSettings.fromJson(saved.toJson()));
      expect(other.load().favoriteShortcut, isFalse);

      // A backup from before the setting existed changes nothing.
      final kept = await repo({'favorite_shortcut': false});
      await kept.applyBackup(BackupSettings.fromJson({'currency': 'USD'}));
      expect(kept.load().favoriteShortcut, isFalse);
      // Something that is not true or false is ignored.
      expect(
        BackupSettings.fromJson({'favoriteShortcut': 'yes'}).favoriteShortcut,
        isNull,
      );
    });
  });

  group('saved filters', () {
    Future<SettingsRepository> repo([Map<String, Object> initial = const {}]) =>
        makeRepo(initial);

    const food = SavedFilter(
      name: 'Food',
      type: TransactionType.expense,
      categoryIds: {2},
      period: SavedPeriod.thisMonth,
      minCents: 500,
      sort: SortOption.highestAmount,
    );
    const rent = SavedFilter(name: 'Rent', categoryIds: {5});

    test('start empty and persist in order', () async {
      final r = await repo();
      expect(r.load().savedFilters, isEmpty);
      await r.setSavedFilters([food, rent]);
      final back = r.load().savedFilters;
      expect(back.map((f) => f.name), ['Food', 'Rent']);
      expect(back.first.minCents, 500);
      expect(back.first.sort, SortOption.highestAmount);
      expect(back.last.categoryIds, {5});
      await r.setSavedFilters(const []);
      expect(r.load().savedFilters, isEmpty);
    });

    test('unreadable stored data is skipped, never thrown', () async {
      expect(
        (await repo({'saved_filters': 'not json'})).load().savedFilters,
        isEmpty,
      );
      expect(
        (await repo({'saved_filters': '{"a":1}'})).load().savedFilters,
        isEmpty,
      );
      final mixed = await repo({
        'saved_filters':
            '[{"name":"Ok","categoryIds":[],"period":"allTime"},{"name":5}]',
      });
      expect(mixed.load().savedFilters.map((f) => f.name), ['Ok']);
    });

    test('travel in a backup and come back', () async {
      final r = await repo();
      await r.setSavedFilters([food, rent]);
      final saved = r.toBackup();
      expect(saved.savedFilters, hasLength(2));

      // Through the JSON a backup file holds.
      final restored = BackupSettings.fromJson(saved.toJson());
      final other = await repo();
      await other.applyBackup(restored);
      expect(other.load().savedFilters.map((f) => f.name), ['Food', 'Rent']);
    });

    test(
      'a backup with none empties them; an older backup leaves them',
      () async {
        final r = await repo();
        await r.setSavedFilters([food]);
        await r.applyBackup(
          BackupSettings.fromJson({'savedFilters': <Object>[]}),
        );
        expect(r.load().savedFilters, isEmpty);

        await r.setSavedFilters([food]);
        await r.applyBackup(BackupSettings.fromJson({'currency': 'USD'}));
        expect(
          r.load().savedFilters,
          hasLength(1),
          reason: 'no key, no change',
        );
      },
    );

    test('a backup keeps only the usable filters', () async {
      final settings = BackupSettings.fromJson({
        'savedFilters': [
          {
            'name': 'Ok',
            'categoryIds': [1],
            'period': 'allTime',
          },
          {'name': '', 'categoryIds': [], 'period': 'allTime'},
          'junk',
        ],
      });
      expect(settings.savedFilters!.map((f) => f.name), ['Ok']);
      expect(
        BackupSettings.fromJson({'savedFilters': 'x'}).savedFilters,
        isNull,
      );
    });
  });

  group('backup reminder settings', () {
    Future<SettingsRepository> repo([Map<String, Object> initial = const {}]) =>
        makeRepo(initial);

    test('are on and not snoozed by default', () async {
      final s = (await repo()).load();
      expect(s.backupReminders, isTrue);
      expect(s.backupSnoozedUntil, isNull);
    });

    test('persist, and the snooze keeps only the day', () async {
      final r = await repo();
      await r.setBackupReminders(false);
      await r.setBackupSnoozedUntil(DateTime(2026, 10, 22, 17, 45));
      final s = r.load();
      expect(s.backupReminders, isFalse);
      expect(s.backupSnoozedUntil, DateTime(2026, 10, 22));
      await r.setBackupReminders(true);
      expect(r.load().backupReminders, isTrue);
    });

    test('a garbled stored snooze reads as none', () async {
      final r = await repo({'backup_snoozed_until': 'soon'});
      expect(r.load().backupSnoozedUntil, isNull);
    });

    test(
      'stay on this phone: not in a backup, not changed by a restore',
      () async {
        final r = await repo({
          'backup_reminders': false,
          'backup_snoozed_until': '2026-10-22',
        });
        final json = r.toBackup().toJson();
        expect(json.keys, isNot(contains('backupReminders')));
        expect(json.keys, isNot(contains('backupSnoozedUntil')));
        expect(json.toString(), isNot(contains('2026-10-22')));

        await r.applyBackup(
          BackupSettings.fromJson({'currency': 'USD', 'backupReminders': true}),
        );
        expect(r.load().backupReminders, isFalse);
        expect(r.load().backupSnoozedUntil, DateTime(2026, 10, 22));
      },
    );

    test('Erase everything forgets them', () async {
      final r = await repo({'backup_reminders': false});
      await r.clearAll();
      expect(r.load().backupReminders, isTrue);
    });
  });
}
