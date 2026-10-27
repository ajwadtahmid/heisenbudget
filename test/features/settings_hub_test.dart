import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/features/settings/settings_screen.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/providers/backup_providers.dart';

import 'test_helpers.dart';

class FakeExchange extends FileExchange {
  final shared = <String>[];
  int cleared = 0;

  @override
  Future<void> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    shared.add(fileName);
  }

  @override
  Future<void> clearTemporaryFiles() async => cleared++;
}

Future<void> openSettings(
  WidgetTester tester,
  TestEnv env, {
  FakeExchange? exchange,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides,
        if (exchange != null) fileExchangeProvider.overrideWithValue(exchange),
      ],
      child: const HeisenbudgetApp(),
    ),
  );
  await settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await settle(tester);
}

Future<void> tapRow(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  // The list builds rows lazily: scroll until a far-down row exists.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300, scrollable: settingsList);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

String? summaryOf(WidgetTester tester, String key) {
  final tile = tester.widget<ListTile>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(ListTile),
    ),
  );
  final sub = tile.subtitle;
  return sub is Text ? sub.data : null;
}

/// The Settings tab's own list (Home and History are in the tree too).
final settingsList = find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  group('the top page', () {
    testWidgets('has the four groups and every row, in order', (tester) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);

      for (final label in [
        'APPEARANCE AND NUMBERS',
        'MANAGE',
        'YOUR DATA',
        'ABOUT',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final order = [
        'settings-appearance',
        'settings-money',
        'manage-categories',
        'manage-recurring',
        'manage-favorites',
        'export-backup',
        'restore-backup',
        'export-csv',
        'erase-everything',
        'settings-about',
      ];
      var last = -1.0;
      for (final key in order) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pump();
        expect(finder, findsOneWidget, reason: key);
      }
      // Top to bottom order, measured in the list (scroll offsets are monotonic).
      final scrollable = tester.state<ScrollableState>(settingsList);
      scrollable.position.jumpTo(0);
      await tester.pump();
      for (final key in order.take(3)) {
        final y = tester.getTopLeft(find.byKey(ValueKey(key))).dy;
        expect(y, greaterThan(last), reason: key);
        last = y;
      }
      await disposeEnv(tester, env);
    });

    testWidgets('no longer holds the controls that moved to sub-pages', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      for (final key in [
        'theme-mode',
        'lab-flavor',
        'currency-dropdown',
        'opening-balance-tile',
        'font-dropdown',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      await disposeEnv(tester, env);
    });

    testWidgets('the rows show live summaries', (tester) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      expect(
        summaryOf(tester, 'settings-appearance'),
        'System · Assay teal · Geist',
      );
      expect(summaryOf(tester, 'settings-money'), 'USD · weeks start Monday');
      expect(summaryOf(tester, 'manage-categories'), '13 categories');
      expect(
        summaryOf(tester, 'manage-recurring'),
        'Rent, salary, subscriptions',
      );
      expect(
        summaryOf(tester, 'manage-favorites'),
        'One tap to log what you buy often',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('summaries follow what is chosen and what exists', (
      tester,
    ) async {
      final env = await createEnv(
        tester,
        prefs: {
          'theme_mode': 'dark',
          'accent': 'violet',
          'text_font': 'inter',
          'currency_code': 'BDT',
          'week_mode': 'fixed',
        },
      );
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await tester.runAsync(() async {
        await FavoriteRepository(env.db).add(
          FavoriteInput(
            label: 'A',
            type: TransactionType.expense,
            categoryId: food,
          ),
        );
        await RecurringRepository(env.db).addWithRule(
          TransactionInput(
            amountCents: 100,
            type: TransactionType.expense,
            date: DateTime(2026, 10, 15),
            categoryId: food,
          ),
          RecurringInput(
            amountCents: 100,
            type: TransactionType.expense,
            categoryId: food,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: DateTime(2026, 10, 15),
          ),
        );
      });
      await openSettings(tester, env);
      expect(summaryOf(tester, 'settings-appearance'), 'Dark · Violet · Inter');
      expect(summaryOf(tester, 'settings-money'), 'BDT · fixed 7-day blocks');
      expect(summaryOf(tester, 'manage-recurring'), '1 repeating transaction');
      expect(summaryOf(tester, 'manage-favorites'), '1 favorite');
      await disposeEnv(tester, env);
    });

    testWidgets('a sub-page change shows in the summary when you come back', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tapRow(tester, 'settings-appearance');
      await tester.tap(find.byKey(const ValueKey('accent-rose')));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(summaryOf(tester, 'settings-appearance'), 'System · Rose · Geist');
      await disposeEnv(tester, env);
    });
  });

  group('the sub-pages', () {
    testWidgets(
      'Appearance holds the look controls and says what Lab flavor changes',
      (tester) async {
        final env = await createEnv(tester);
        await openSettings(tester, env);
        await tapRow(tester, 'settings-appearance');
        expect(find.text('Appearance'), findsWidgets);
        for (final key in [
          'theme-mode',
          'accent-assay',
          'font-dropdown',
          'lab-flavor',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
        expect(
          find.byKey(const ValueKey('lab-flavor-effect')),
          findsNWidgets(3),
        );
        expect(find.textContaining('PURITY, or SAVED'), findsOneWidget);
        expect(find.textContaining('SPECTRUM, or SPENDING'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('Money & dates holds currency, opening balance and weeks', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tapRow(tester, 'settings-money');
      expect(find.text('Money & dates'), findsWidgets);
      for (final key in ['currency-dropdown', 'opening-balance-tile']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('Calendar weeks'), findsOneWidget);
      expect(find.text('Fixed 7-day blocks'), findsOneWidget);
      expect(find.text('Week starts on'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('Your data', () {
    testWidgets('says "Not backed up yet" until a backup is made', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env, exchange: FakeExchange());
      expect(summaryOf(tester, 'export-backup'), 'Not backed up yet');
      await disposeEnv(tester, env);
    });

    testWidgets('making a backup records the date and shows it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final exchange = FakeExchange();
      await openSettings(tester, env, exchange: exchange);
      await tapRow(tester, 'export-backup');

      expect(exchange.shared.single, 'heisenbudget-backup-2026-10-15.json');
      expect(
        summaryOf(tester, 'export-backup'),
        'Last backup file: Oct 15, 2026',
      );
      expect(env.prefs.getString('last_backup_at'), isNotNull);
      await disposeEnv(tester, env);
    });

    testWidgets('a CSV export does not count as a backup', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 100, DateTime(2026, 10, 1));
      final exchange = FakeExchange();
      await openSettings(tester, env, exchange: exchange);
      await tapRow(tester, 'export-csv');
      expect(exchange.shared, hasLength(1));
      expect(summaryOf(tester, 'export-backup'), 'Not backed up yet');
      await disposeEnv(tester, env);
    });

    testWidgets('30 days old is still quiet; 31 days says how many days ago', (
      tester,
    ) async {
      final env = await createEnv(
        tester,
        prefs: {
          'last_backup_at': DateTime(2026, 9, 15, 12).toUtc().toIso8601String(),
        },
      );
      await openSettings(tester, env, exchange: FakeExchange());
      expect(
        summaryOf(tester, 'export-backup'),
        'Last backup file: Sep 15, 2026',
      );
      await disposeEnv(tester, env);

      final env2 = await createEnv(
        tester,
        prefs: {
          'last_backup_at': DateTime(2026, 9, 14, 12).toUtc().toIso8601String(),
        },
      );
      await openSettings(tester, env2, exchange: FakeExchange());
      expect(
        summaryOf(tester, 'export-backup'),
        'Last backup file: Sep 14, 2026 · 31 days ago',
      );
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('export-backup')),
          matching: find.textContaining('31 days ago'),
        ),
      );
      expect(text.style?.fontWeight, FontWeight.w600, reason: 'not dim');
      await disposeEnv(tester, env2);
    });
  });

  group('About', () {
    testWidgets('Settings has one About row, and no licences or data rows', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tester.ensureVisible(find.byKey(const ValueKey('settings-about')));
      await tester.pump();
      expect(find.text('About Heisenbudget'), findsOneWidget);
      expect(summaryOf(tester, 'settings-about'), 'Version 1.0.0');
      for (final key in [
        'settings-version',
        'settings-data-kept',
        'settings-licences',
        'settings-disclaimer',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      expect(find.text('Licences'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'the About screen shows the name, version and a short description',
      (tester) async {
        final env = await createEnv(tester);
        await openSettings(tester, env);
        await tapRow(tester, 'settings-about');
        expect(
          find.text('About Heisenbudget'),
          findsOneWidget,
          reason: 'app bar',
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('about-name'))).data,
          'Heisenbudget',
        );
        expect(find.text('Version 1.0.0'), findsOneWidget);
        expect(
          find.textContaining('private expense and income tracker'),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets('it gives the privacy policy address and can copy it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tapRow(tester, 'settings-about');
      expect(find.text('Privacy policy'.toUpperCase()), findsOneWidget);
      expect(
        find.text(
          'https://ajwadtahmid.github.io/privacy-policies/Heisenbudget.html',
        ),
        findsOneWidget,
      );

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('about-copy-link')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('about-copy-link')));
      await settle(tester);
      expect(copied, privacyPolicyUrl);
      expect(find.text('Link copied.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('it opens the open-source licences page', (tester) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tapRow(tester, 'settings-about');
      expect(find.text('OPEN-SOURCE LICENCES'), findsOneWidget);

      final button = find.byKey(const ValueKey('about-licences'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text(appName), findsWidgets);
      expect(find.text(appVersion), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'it explains how the data is kept and says it is not affiliated',
      (tester) async {
        final env = await createEnv(tester);
        await openSettings(tester, env);
        await tapRow(tester, 'settings-about');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('about-disclaimer')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('HOW YOUR DATA IS KEPT'), findsOneWidget);
        expect(find.text('It stays on this phone.'), findsOneWidget);
        expect(
          find.textContaining('never connects to the internet'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Not affiliated with or endorsed by'),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets('the app opens no web page and has no browser plugin', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSettings(tester, env);
      await tapRow(tester, 'settings-about');
      // The address is plain, selectable text: nothing here can go online.
      expect(find.byKey(const ValueKey('about-privacy-url')), findsOneWidget);
      expect(
        tester.widget(find.byKey(const ValueKey('about-privacy-url'))),
        isA<SelectableText>(),
      );
      await disposeEnv(tester, env);
    });
  });

  group('Erase everything', () {
    Future<void> seed(WidgetTester tester, TestEnv env) async {
      await addExpense(tester, env, 450, DateTime(2026, 10, 5), note: 'Latte');
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await tester.runAsync(
        () => FavoriteRepository(env.db).add(
          FavoriteInput(
            label: 'F',
            type: TransactionType.expense,
            categoryId: food,
          ),
        ),
      );
    }

    Future<int> txCount(WidgetTester tester, TestEnv env) async =>
        (await tester.runAsync(() => env.db.select(env.db.transactions).get()))!
            .length;

    testWidgets('warns first, and Cancel changes nothing', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await openSettings(tester, env, exchange: FakeExchange());
      await tapRow(tester, 'erase-everything');
      expect(find.text('Erase everything?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('erase-cancel')));
      await settle(tester);
      expect(await txCount(tester, env), 1);
      await disposeEnv(tester, env);
    });

    testWidgets('"Back up first" makes a backup and erases nothing', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      final exchange = FakeExchange();
      await openSettings(tester, env, exchange: exchange);
      await tapRow(tester, 'erase-everything');
      await tester.tap(find.byKey(const ValueKey('erase-backup-first')));
      await settle(tester);
      expect(exchange.shared.single, startsWith('heisenbudget-backup-'));
      expect(await txCount(tester, env), 1);
      expect(find.text('Erase everything now?'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('the second step can still back out', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await openSettings(tester, env, exchange: FakeExchange());
      await tapRow(tester, 'erase-everything');
      await tester.tap(find.byKey(const ValueKey('erase-continue')));
      await settle(tester);
      expect(find.text('Erase everything now?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('erase-keep')));
      await settle(tester);
      expect(await txCount(tester, env), 1);
      await disposeEnv(tester, env);
    });

    testWidgets('confirming wipes the data and returns to the welcome tour', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'currency_code': 'BDT'});
      await seed(tester, env);
      final exchange = FakeExchange();
      await openSettings(tester, env, exchange: exchange);
      await tapRow(tester, 'erase-everything');
      await tester.tap(find.byKey(const ValueKey('erase-continue')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('erase-confirm')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(await txCount(tester, env), 0);
      expect(
        (await tester.runAsync(() => env.db.select(env.db.favorites).get()))!,
        isEmpty,
      );
      expect(
        (await tester.runAsync(() => env.db.select(env.db.categories).get()))!
            .length,
        13,
      );
      expect(env.prefs.getString('currency_code'), isNull);
      expect(exchange.cleared, 1, reason: 'temporary export files removed');
      expect(find.byKey(const ValueKey('welcome-skip')), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    testWidgets(
      'the top page and sub-pages fit at 200% text on a small screen',
      (tester) async {
        final env = await createEnv(tester);
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openSettings(tester, env, exchange: FakeExchange());
        expect(tester.takeException(), isNull, reason: 'the top page');

        // Scroll the whole page.
        await tester.drag(settingsList, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'bottom of the page');
        tester.state<ScrollableState>(settingsList).position.jumpTo(0);
        await tester.pump();

        for (final row in ['settings-appearance', 'settings-money']) {
          await tapRow(tester, row);
          expect(tester.takeException(), isNull, reason: row);
          await tester.drag(
            find.byType(Scrollable).last,
            const Offset(0, -2000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$row scrolled');
          await tester.pageBack();
          await settle(tester);
        }
        await tapRow(tester, 'settings-about');
        expect(tester.takeException(), isNull, reason: 'about page');
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'about page scrolled');
        await disposeEnv(tester, env);
      },
    );
  });
}
