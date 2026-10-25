import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/design/tick_ruler.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/features/home/home_screen.dart';

import 'test_helpers.dart';

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

/// Scrolls a Settings control into view first: the page is long.
Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Opens the font dropdown and chooses an entry by its label.
Future<void> pickFont(WidgetTester tester, String label) async {
  final dropdown = find.byKey(const ValueKey('font-dropdown'));
  await tester.ensureVisible(dropdown);
  await tester.pump();
  await tester.tap(dropdown);
  await settle(tester);
  // The menu is the last thing in the tree ("System" also names a theme mode).
  await tester.tap(find.text(label).last);
  await settle(tester);
}

String balanceText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('balance'))).data!;

ThemeData currentTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

Finder inRow(String row, String text) => find.descendant(
  of: find.byKey(ValueKey('row-$row')),
  matching: find.text(text),
);

void main() {
  group('Home: the instrument readout', () {
    testWidgets('has the readout, ruled rows, ruler, spectrum and ledger', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 100000, DateTime(2026, 10, 1));
      await addExpense(tester, env, 2500, DateTime(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      expect(find.text('HEISENBUDGET'), findsOneWidget);
      expect(find.byKey(const ValueKey('balance')), findsOneWidget);
      for (final row in ['received', 'spent', 'net']) {
        expect(find.byKey(ValueKey('row-$row')), findsOneWidget, reason: row);
      }
      expect(find.byType(TickRuler), findsOneWidget);
      expect(find.byKey(const ValueKey('spectrum-chart')), findsOneWidget);
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('SPECTRUM'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the balance is a big mono readout', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      final style = tester
          .widget<Text>(find.byKey(const ValueKey('balance')))
          .style!;
      expect(style.fontFamily, 'GeistMono');
      expect(style.fontSize, 44);
      await disposeEnv(tester, env);
    });

    testWidgets('the add key is a quiet icon-only + on Home and History', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      for (final tab in ['Home', 'History']) {
        await goToTab(tester, tab);
        final key = find.byType(FloatingActionButton);
        expect(key, findsOneWidget, reason: tab);
        expect(find.byIcon(Icons.add), findsOneWidget, reason: tab);
        expect(find.text('LOG'), findsNothing);
        expect(find.text('ADD'), findsNothing);
        expect(find.byTooltip('Add transaction'), findsOneWidget);
        expect(tester.getSize(key).width, greaterThanOrEqualTo(48));
      }
      await disposeEnv(tester, env);
    });

    testWidgets('the add key opens the Add sheet from History too', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Add transaction'), findsWidgets);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'the add key is tonal with an accent outline, not a solid slab',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wrap(env, const HomeScreen()));
        await settle(tester);
        final theme = currentTheme(tester);
        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );
        expect(fab.heroTag, isNull);
        expect(
          theme.floatingActionButtonTheme.backgroundColor,
          theme.colorScheme.primaryContainer,
        );
        expect(
          theme.floatingActionButtonTheme.foregroundColor,
          theme.extension<AppColors>()!.accent,
        );
        final shape =
            theme.floatingActionButtonTheme.shape as RoundedRectangleBorder;
        expect(shape.side.width, 1);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('pushing a page is safe with two add keys in the tab stack', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await goToTab(tester, 'Settings');
      await tester.ensureVisible(
        find.byKey(const ValueKey('manage-categories')),
      );
      await tester.tap(find.byKey(const ValueKey('manage-categories')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Categories'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('PURITY (Lab flavor)', () {
    testWidgets('is the share of income you kept', (tester) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 100000, DateTime(2026, 10, 1));
      await addExpense(tester, env, 25000, DateTime(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.text('PURITY 75.0%'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('overspending reads 0.0%, never negative', (tester) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 1000, DateTime(2026, 10, 1));
      await addExpense(tester, env, 5000, DateTime(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.text('PURITY 0.0%'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('is hidden when nothing came in', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 5000, DateTime(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('purity')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('is called SAVED in plain wording when Lab flavor is off', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'lab_flavor': false});
      await addIncome(tester, env, 100000, DateTime(2026, 10, 1));
      await addExpense(tester, env, 25000, DateTime(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.text('SAVED 75.0%'), findsOneWidget);
      expect(find.textContaining('PURITY'), findsNothing);
      expect(find.text('SPENDING'), findsOneWidget);
      expect(find.text('SPECTRUM'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'plain SAVED follows the same rules: 0.0% when overspent, hidden with no income',
      (tester) async {
        final over = await createEnv(tester, prefs: {'lab_flavor': false});
        await addIncome(tester, over, 1000, DateTime(2026, 10, 1));
        await addExpense(tester, over, 5000, DateTime(2026, 10, 2));
        await tester.pumpWidget(wrap(over, const HomeScreen()));
        await settle(tester);
        expect(find.text('SAVED 0.0%'), findsOneWidget);
        await disposeEnv(tester, over);

        final none = await createEnv(tester, prefs: {'lab_flavor': false});
        await addExpense(tester, none, 5000, DateTime(2026, 10, 2));
        await tester.pumpWidget(wrap(none, const HomeScreen()));
        await settle(tester);
        expect(find.byKey(const ValueKey('purity')), findsNothing);
        await disposeEnv(tester, none);
      },
    );

    testWidgets('switching Lab flavor swaps PURITY and SAVED live', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 100000, DateTime(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('PURITY 100.0%'), findsOneWidget);

      await goToTab(tester, 'Settings');
      await tapScrolled(tester, find.byKey(const ValueKey('lab-flavor')));
      await goToTab(tester, 'Home');
      expect(find.text('SAVED 100.0%'), findsOneWidget);
      expect(find.text('PURITY 100.0%'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('empty states use the flavor wording', (tester) async {
      final lab = await createEnv(tester);
      await tester.pumpWidget(wrap(lab, const HomeScreen()));
      await settle(tester);
      expect(find.textContaining('Flat line'), findsWidgets);
      await disposeEnv(tester, lab);

      final plain = await createEnv(tester, prefs: {'lab_flavor': false});
      await tester.pumpWidget(wrap(plain, const HomeScreen()));
      await settle(tester);
      expect(find.textContaining('Flat line'), findsNothing);
      expect(find.textContaining('No transactions yet'), findsOneWidget);
      await disposeEnv(tester, plain);
    });
  });

  group('opening balance on Home', () {
    testWidgets('counts toward the balance but not Received', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {'opening_balance_cents': 50000},
      );
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(balanceText(tester), r'$500.00');
      expect(inRow('received', r'$0.00'), findsOneWidget);
      expect(inRow('net', r'$0.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('purity')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a negative opening balance shows in amber', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {'opening_balance_cents': -2500},
      );
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(balanceText(tester), r'-$25.00');
      final style = tester
          .widget<Text>(find.byKey(const ValueKey('balance')))
          .style!;
      expect(style.color, currentTheme(tester).extension<AppColors>()!.spent);
      await disposeEnv(tester, env);
    });
  });

  group('spectrum chart', () {
    Future<TestEnv> seeded(WidgetTester tester) async {
      final env = await createEnv(tester);
      await addExpense(
        tester,
        env,
        3000,
        DateTime(2026, 10, 2),
        category: 'Rent',
      );
      await addExpense(tester, env, 1000, DateTime(2026, 10, 3));
      return env;
    }

    testWidgets('draws one peak per category, tallest first', (tester) async {
      final env = await seeded(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      expect(find.byKey(const ValueKey('spectrum-bar-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('spectrum-bar-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('spectrum-bar-2')), findsNothing);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);

      double peak(int i) => tester
          .getSize(
            find.descendant(
              of: find.byKey(ValueKey('spectrum-bar-$i')),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .height;
      expect(peak(0), greaterThan(peak(1)));
      expect(peak(1) / peak(0), closeTo(1 / 3, 0.02));
      await disposeEnv(tester, env);
    });

    testWidgets('top five plus a Rest peak', (tester) async {
      final env = await createEnv(tester);
      var day = 1;
      for (final (name, cents) in [
        ('Rent', 7000),
        ('Food', 6000),
        ('Travel', 5000),
        ('Shopping', 4000),
        ('Medical', 3000),
        ('Bills', 2000),
        ('Transport', 1000),
      ]) {
        await addExpense(
          tester,
          env,
          cents,
          DateTime(2026, 10, day++),
          category: name,
        );
      }
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      for (var i = 0; i < 6; i++) {
        expect(
          find.byKey(ValueKey('spectrum-bar-$i')),
          findsOneWidget,
          reason: '$i',
        );
      }
      expect(find.byKey(const ValueKey('spectrum-bar-6')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spectrum-bar-5')),
          matching: find.text('Rest'),
        ),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('tap a peak to focus it, tap again to clear', (tester) async {
      final env = await seeded(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.text('Tap a peak for detail'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spectrum-bar-0')));
      await settle(tester);
      expect(find.text('RENT · 75.0%'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spectrum-readout')),
          matching: find.text(r'$30.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Tap a peak for detail'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('spectrum-bar-1')));
      await settle(tester);
      expect(find.text('FOOD · 25.0%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('spectrum-bar-1')));
      await settle(tester);
      expect(find.text('Tap a peak for detail'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('each peak is a labelled button for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await seeded(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      expect(find.bySemanticsLabel(r'Rent, 75.0%, $30.00'), findsOneWidget);
      expect(find.bySemanticsLabel(r'Food, 25.0%, $10.00'), findsOneWidget);
      handle.dispose();
      await disposeEnv(tester, env);
    });

    testWidgets('an empty period shows a flat line and a message', (
      tester,
    ) async {
      final env = await seeded(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      await swipePeriod(tester, forward: true);
      expect(find.byKey(const ValueKey('spectrum-bar-0')), findsNothing);
      expect(
        find.textContaining('Nothing spent in this period'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('income is not part of the spending chart', (tester) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 900000, DateTime(2026, 10, 1));
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('spectrum-bar-0')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('fits a 320dp screen at 200% text', (tester) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(320, 700);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var day = 1;
      for (final name in [
        'Rent',
        'Food',
        'Travel',
        'Shopping',
        'Medical',
        'Bills',
        'Transport',
      ]) {
        await addExpense(
          tester,
          env,
          99999999999 - day * 1000,
          DateTime(2026, 10, day++),
          category: name,
        );
      }
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('Settings: appearance', () {
    testWidgets(
      'lists every accent as a 48dp target and the fonts as one dropdown',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wholeApp(env));
        await goToTab(tester, 'Settings');

        for (final accent in AccentColor.values) {
          final finder = find.byKey(ValueKey('accent-${accent.name}'));
          expect(finder, findsOneWidget, reason: accent.name);
          final size = tester.getSize(finder);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(find.byKey(const ValueKey('font-dropdown')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('font-dropdown'))).height,
          lessThanOrEqualTo(64),
          reason: 'one line, not a wrapping set of chips',
        );
        expect(find.byType(ChoiceChip), findsNothing);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('choosing an accent restyles the app and is remembered', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');

      await tapScrolled(tester, find.byKey(const ValueKey('accent-ice')));

      final theme = currentTheme(tester);
      expect(
        theme.colorScheme.primary,
        AccentColor.ice.forBrightness(theme.brightness),
      );
      expect(env.prefs.getString('accent'), 'ice');

      await tapScrolled(tester, find.byKey(const ValueKey('accent-rose')));
      expect(
        currentTheme(tester).colorScheme.primary,
        AccentColor.rose.forBrightness(theme.brightness),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the accent never changes Received and Spent', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      final before = currentTheme(tester).extension<AppColors>()!;
      await goToTab(tester, 'Settings');
      await tapScrolled(tester, find.byKey(const ValueKey('accent-violet')));
      final after = currentTheme(tester).extension<AppColors>()!;
      expect(after.received, before.received);
      expect(after.spent, before.spent);
      expect(after.accent, isNot(before.accent));
      await disposeEnv(tester, env);
    });

    testWidgets('choosing a font restyles all text, numbers stay mono', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      expect(currentTheme(tester).textTheme.bodyMedium!.fontFamily, 'Geist');

      await pickFont(tester, 'Inter');
      expect(currentTheme(tester).textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(env.prefs.getString('text_font'), 'inter');

      await pickFont(tester, 'Atkinson Hyperlegible');
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        'AtkinsonHyperlegible',
      );

      await pickFont(tester, 'System');
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        isNot(anyOf('Geist', 'Inter', 'AtkinsonHyperlegible')),
      );

      await goToTab(tester, 'Home');
      final balance = tester.widget<Text>(
        find.byKey(const ValueKey('balance')),
      );
      expect(
        balance.style!.fontFamily,
        'GeistMono',
        reason: 'numbers ignore the text font',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('every font fits Home at 200% text on a small screen', (
      tester,
    ) async {
      for (final font in AppFont.values) {
        final env = await createEnv(tester, prefs: {'text_font': font.name});
        tester.view.physicalSize = const Size(360, 700);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        await addIncome(tester, env, 450000, DateTime(2026, 10, 1));
        await addExpense(
          tester,
          env,
          125000,
          DateTime(2026, 10, 2),
          category: 'Entertainment',
          note: 'A fairly long note for the list',
        );
        await tester.pumpWidget(wrap(env, const HomeScreen()));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: font.name);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await disposeEnv(tester, env);
      }
    });

    testWidgets('the Lab flavor switch changes the wording on Home', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('lab-flavor')))
            .value,
        isTrue,
        reason: 'on by default',
      );

      await tapScrolled(tester, find.byKey(const ValueKey('lab-flavor')));
      expect(env.prefs.getBool('lab_flavor'), isFalse);

      await goToTab(tester, 'Home');
      expect(find.text('SPENDING'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('Settings: opening balance', () {
    Future<void> open(WidgetTester tester) async {
      await tapScrolled(
        tester,
        find.byKey(const ValueKey('opening-balance-tile')),
      );
    }

    testWidgets('can be set, including negative, and moves the balance', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');

      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('opening-balance-field')),
        '250,50',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), 25050);
      expect(find.text(r'$250.50'), findsOneWidget);

      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('opening-balance-field')),
        '-40',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), -4000);

      await goToTab(tester, 'Home');
      expect(balanceText(tester), r'-$40.00');
      await disposeEnv(tester, env);
    });

    testWidgets('rejects unusable input and keeps the old value', (
      tester,
    ) async {
      final env = await createEnv(
        tester,
        prefs: {'opening_balance_cents': 1000},
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');

      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('opening-balance-field')),
        '1,234.56',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
        find.text('Enter the amount without thousands separators'),
        findsOneWidget,
      );
      expect(env.prefs.getInt('opening_balance_cents'), 1000);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), 1000);
      await disposeEnv(tester, env);
    });

    testWidgets('can be cleared back to zero', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {'opening_balance_cents': 1000},
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('opening-balance-field')),
        '0',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), 0);
      await disposeEnv(tester, env);
    });
  });

  group('first-run welcome', () {
    Future<TestEnv> fresh(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
    }) async {
      final env = await createEnv(
        tester,
        prefs: {'onboarding_done': false, ...prefs},
      );
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      return env;
    }

    testWidgets('a fresh install starts with the tour, not the app', (
      tester,
    ) async {
      final env = await fresh(tester);
      expect(find.byKey(const ValueKey('welcome-next')), findsOneWidget);
      expect(find.textContaining('measured'), findsOneWidget);
      expect(find.text('Works fully offline'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'three steps, then the app; an empty opening balance is skipped',
      (tester) async {
        final env = await fresh(tester);
        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
        expect(find.text('Make it yours'), findsOneWidget);
        expect(find.byKey(const ValueKey('currency-dropdown')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
        expect(find.text('Opening balance'), findsOneWidget);
        expect(find.text('Finish'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(env.prefs.getBool('onboarding_done'), isTrue);
        expect(env.prefs.getInt('opening_balance_cents'), isNull);
        expect(balanceText(tester), r'$0.00');
        await disposeEnv(tester, env);
      },
    );

    testWidgets('an opening balance entered in the tour becomes the balance', (
      tester,
    ) async {
      final env = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('opening-field')),
        '1234.50',
      );
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      expect(env.prefs.getInt('opening_balance_cents'), 123450);
      expect(balanceText(tester), r'$1,234.50');
      await disposeEnv(tester, env);
    });

    testWidgets('a bad opening balance keeps you on the page with an error', (
      tester,
    ) async {
      final env = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('opening-field')),
        '1,234.56',
      );
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      expect(
        find.text('Enter the amount without thousands separators'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(env.prefs.getBool('onboarding_done'), isNot(true));

      // Fixing it lets you finish.
      await tester.enterText(
        find.byKey(const ValueKey('opening-field')),
        '1234.56',
      );
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), 123456);
      await disposeEnv(tester, env);
    });

    testWidgets('a negative opening balance is allowed', (tester) async {
      final env = await fresh(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
      }
      await tester.enterText(
        find.byKey(const ValueKey('opening-field')),
        '-75',
      );
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      expect(env.prefs.getInt('opening_balance_cents'), -7500);
      await disposeEnv(tester, env);
    });

    testWidgets('Skip leaves at once, from any step', (tester) async {
      final env = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-skip')));
      await settle(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(env.prefs.getBool('onboarding_done'), isTrue);
      await disposeEnv(tester, env);

      final second = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-skip')));
      await settle(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      await disposeEnv(tester, second);
    });

    testWidgets('Back returns to the previous step', (tester) async {
      final env = await fresh(tester);
      expect(find.byKey(const ValueKey('welcome-back')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-back')));
      await settle(tester);
      expect(find.textContaining('measured'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('choices made in the tour apply at once and are saved', (
      tester,
    ) async {
      final env = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('accent-rose')));
      await settle(tester);
      expect(env.prefs.getString('accent'), 'rose');
      final theme = currentTheme(tester);
      expect(
        theme.colorScheme.primary,
        AccentColor.rose.forBrightness(theme.brightness),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('theme-mode')),
          matching: find.text('Dark'),
        ),
      );
      await settle(tester);
      expect(env.prefs.getString('theme_mode'), 'dark');
      expect(currentTheme(tester).brightness, Brightness.dark);
      await disposeEnv(tester, env);
    });

    testWidgets('a currency chosen in the tour shows on the next page', (
      tester,
    ) async {
      final env = await fresh(tester);
      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('currency-dropdown')),
          matching: find.byType(TextField),
        ),
        'bangla',
      );
      await settle(tester);
      await tester.tap(find.text('৳ Bangladeshi Taka (BDT)'));
      await settle(tester);
      expect(env.prefs.getString('currency_code'), 'BDT');

      await tester.tap(find.byKey(const ValueKey('welcome-next')));
      await settle(tester);
      expect(
        find.text('৳ '),
        findsOneWidget,
        reason: 'prefix of the amount field',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('people who already have data never see the tour', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'onboarding_done': false});
      await addExpense(tester, env, 500, DateTime(2026, 10, 2));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      expect(find.byKey(const ValueKey('welcome-next')), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(env.prefs.getBool('onboarding_done'), isTrue);
      await disposeEnv(tester, env);
    });

    testWidgets('once done, the tour never comes back', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.byKey(const ValueKey('welcome-next')), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('fits a small screen at 200% text', (tester) async {
      final env = await createEnv(tester, prefs: {'onboarding_done': false});
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        expect(tester.takeException(), isNull, reason: 'page $i');
        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('History at scale, with pinned day headers', () {
    testWidgets('hundreds of rows build and scroll without errors', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 600; i++) {
          await env.txs.add(
            TransactionInput(
              amountCents: 100 + i,
              type: TransactionType.expense,
              date: DateTime(2026, 10, 13 - (i % 120)),
              categoryId: food,
            ),
          );
        }
      });
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Tue, Oct 13, 2026'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('a day\'s header stays at the top while its rows scroll', (
      tester,
    ) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(400, 500); // short: it must scroll
      for (var i = 0; i < 12; i++) {
        await addExpense(tester, env, 1000 + i, DateTime(2026, 10, 13));
      }
      await addExpense(tester, env, 500, DateTime(2026, 10, 12));
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);

      final header = find.text('Tue, Oct 13, 2026');
      expect(header, findsOneWidget);
      final before = tester.getTopLeft(header).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(header, findsOneWidget, reason: 'still on screen after scrolling');
      expect(tester.getTopLeft(header).dy, lessThanOrEqualTo(before + 1));
      final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      expect(
        tester.getTopLeft(header).dy,
        lessThan(listTop + 48),
        reason: 'pinned at the top of the list',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the next day pushes the pinned header away', (tester) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(400, 500); // short: it must scroll
      await addExpense(tester, env, 1000, DateTime(2026, 10, 13));
      for (var i = 0; i < 12; i++) {
        await addExpense(tester, env, 1000 + i, DateTime(2026, 10, 12));
      }
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mon, Oct 12, 2026'), findsOneWidget);
      expect(
        find.text('Tue, Oct 13, 2026'),
        findsNothing,
        reason: 'scrolled out; only the current day is pinned',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('each header shows that day\'s net', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 100, DateTime(2026, 10, 13));
      await addExpense(tester, env, 50, DateTime(2026, 10, 13));
      await addIncome(tester, env, 1000, DateTime(2026, 10, 13));
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      expect(find.text(r'+$8.50'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('shell', () {
    testWidgets('a hairline separates the tab bar from the page', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      expect(
        find.ancestor(of: bar, matching: find.byType(Column)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.ancestor(of: bar, matching: find.byType(Column)).first,
          matching: find.byType(Divider),
        ),
        findsWidgets,
      );
      await disposeEnv(tester, env);
    });
  });

  group('review fixes', () {
    testWidgets('the add key is the same small icon key at every text size', (
      tester,
    ) async {
      final env = await createEnv(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(
        tester.getSize(find.byType(FloatingActionButton)).width,
        lessThan(80),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a one-entry day shows no repeated total; a busy day does', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 700, DateTime(2026, 10, 13)); // one entry
      await addExpense(tester, env, 100, DateTime(2026, 10, 12));
      await addExpense(tester, env, 250, DateTime(2026, 10, 12)); // two entries
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);

      expect(find.text('Tue, Oct 13, 2026'), findsOneWidget);
      // The one-entry day's amount appears once (on its row), not twice.
      expect(find.text(r'-$7.00'), findsOneWidget);
      // The two-entry day gets a header total.
      expect(find.text(r'-$3.50'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('day headers are a tonal band', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 700, DateTime(2026, 10, 13));
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      final header = find.ancestor(
        of: find.text('Tue, Oct 13, 2026'),
        matching: find.byType(Container),
      );
      final box = tester.widget<Container>(header.first);
      final decoration = box.decoration as BoxDecoration;
      expect(
        decoration.color,
        currentTheme(tester).extension<AppColors>()!.panel,
      );
      await disposeEnv(tester, env);
    });

    testWidgets(
      'selected category chip: no checkmark over the icon, icon in accent',
      (tester) async {
        final env = await createEnv(tester);
        await openForm(tester, env);
        final food = await categoryId(
          tester,
          env,
          'Food',
          TransactionType.expense,
        );
        await tester.tap(find.byKey(ValueKey('category-$food')));
        await tester.pump();

        final chip = tester.widget<ChoiceChip>(
          find.byKey(ValueKey('category-$food')),
        );
        expect(chip.selected, isTrue);
        expect(chip.showCheckmark, isFalse);
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey('category-$food')),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.color, currentTheme(tester).extension<AppColors>()!.accent);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('amount fields always show their currency symbol', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      expect(find.text(r'$ '), findsOneWidget, reason: 'even while empty');
      await disposeEnv(tester, env);

      final tour = await createEnv(tester, prefs: {'onboarding_done': false});
      await tester.pumpWidget(wholeApp(tour));
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('welcome-next')));
        await settle(tester);
      }
      expect(find.text(r'$ '), findsOneWidget);
      await disposeEnv(tester, tour);
    });

    testWidgets('the welcome has no kicker above its heading', (tester) async {
      final env = await createEnv(tester, prefs: {'onboarding_done': false});
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('HEISENBUDGET'), findsNothing);
      expect(find.textContaining('measured'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('Settings subheads are quieter than the section labels', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      final section = tester.widget<Text>(find.text('APPEARANCE'));
      final sub = tester.widget<Text>(find.text('Accent'));
      final colors = currentTheme(tester).extension<AppColors>()!;
      expect(sub.style!.color, colors.dim);
      expect(sub.style!.fontWeight, isNot(FontWeight.w700));
      expect(section.style?.fontWeight ?? FontWeight.w600, FontWeight.w600);
      await disposeEnv(tester, env);
    });
  });
}
