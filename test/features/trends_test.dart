import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/features/home/home_screen.dart';
import 'package:heisenbudget/features/trends/trends_screen.dart';
import 'package:heisenbudget/providers/trends_providers.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// Home, scrolled until [key] is built and on screen (a long list builds only
/// what is near the screen).
Future<void> reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// A labelled figure in the readouts, which are one piece of rich text.
Finder figure(String text) => find.textContaining(text, findRichText: true);

/// Jul, Aug and Sep 2026 of steady spending, and a little in October (today
/// is Oct 15): the glance and the page have something to say.
Future<TestEnv> withHistory(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  final env = await createEnv(tester, prefs: prefs);
  await addIncome(tester, env, 200000, d(2026, 7, 1));
  await addExpense(tester, env, 10000, d(2026, 7, 9), category: 'Food');
  await addIncome(tester, env, 200000, d(2026, 8, 1));
  await addExpense(tester, env, 10000, d(2026, 8, 9), category: 'Food');
  await addExpense(tester, env, 30000, d(2026, 8, 10), category: 'Rent');
  await addIncome(tester, env, 200000, d(2026, 9, 1));
  await addExpense(tester, env, 20000, d(2026, 9, 9), category: 'Food');
  await addExpense(tester, env, 10000, d(2026, 9, 10), category: 'Rent');
  await addExpense(tester, env, 1000, d(2026, 10, 2), category: 'Food');
  await addExpense(tester, env, 2500, d(2026, 10, 5), category: 'Rent');
  await addExpense(tester, env, 500, d(2026, 10, 5), category: 'Food');
  return env;
}

Future<void> openHome(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
}

Future<void> openTrendsPage(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wrap(env, const TrendsScreen()));
  await settle(tester);
}

void main() {
  group('Home glance', () {
    testWidgets('says nothing until something has been logged', (tester) async {
      final env = await createEnv(tester);
      await openHome(tester, env);
      expect(find.byKey(const ValueKey('trend-glance')), findsNothing);
      expect(find.text('TRACE · LAST 6 MONTHS'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('six small peaks and how the last month compares', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openHome(tester, env);
      await reveal(tester, 'trend-glance');

      expect(find.text('TRACE · LAST 6 MONTHS'), findsOneWidget);
      for (final month in ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('trend-glance')),
            matching: find.text(month),
          ),
          findsOneWidget,
          reason: month,
        );
      }
      // Sep 300.00 against Jul 100.00 and Aug 400.00: 250.00 on average.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('trend-glance-text')))
            .data,
        r'September: spent $300.00, 20% over your 2-month average.',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('with Lab flavor off it says Trends', (tester) async {
      final env = await withHistory(tester, prefs: {'lab_flavor': false});
      await openHome(tester, env);
      await reveal(tester, 'trend-glance');
      expect(find.text('TRENDS · LAST 6 MONTHS'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('one month of history cannot be compared yet', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 1000, d(2026, 10, 2));
      await openHome(tester, env);
      await reveal(tester, 'trend-glance');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('trend-glance-text')))
            .data,
        'A second month of history unlocks the comparison.',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('See all and the peaks both open the Trends page', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openHome(tester, env);
      await reveal(tester, 'trend-glance');

      await tester.tap(find.byKey(const ValueKey('glance-see-all')));
      await settle(tester);
      expect(find.byType(TrendsScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(TrendsScreen), findsNothing);

      await reveal(tester, 'trend-glance');
      await tester.tap(find.byKey(const ValueKey('trend-glance')));
      await settle(tester);
      expect(find.byType(TrendsScreen), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await withHistory(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, env);
      await reveal(tester, 'trend-glance');
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('Trends page', () {
    testWidgets('draws the months, and a month can be focused', (tester) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);

      expect(find.text('Money in and out'.toUpperCase()), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('trace-month-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('trace-month-6')), findsNothing);
      expect(find.text('Tap a month for detail'), findsOneWidget);

      // The fifth of six months is September.
      await tester.tap(find.byKey(const ValueKey('trace-month-4')));
      await settle(tester);
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
      expect(figure(r'+$2,000.00'), findsOneWidget);
      expect(figure(r'-$300.00'), findsOneWidget);
      expect(find.text('Tap a month for detail'), findsNothing);

      // The month still going says so.
      await tester.tap(find.byKey(const ValueKey('trace-month-5')));
      await settle(tester);
      expect(find.text('OCTOBER 2026 · SO FAR'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('twelve months doubles the peaks', (tester) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      await tester.tap(find.byKey(const ValueKey('trend-window-12')));
      await settle(tester);
      expect(find.byKey(const ValueKey('trace-month-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('trace-month-12')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('trend-window-6')));
      await settle(tester);
      expect(find.byKey(const ValueKey('trace-month-6')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('the same months can be read as a list, newest first', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      await tester.tap(find.byKey(const ValueKey('trace-list-toggle')));
      await settle(tester);

      expect(find.byKey(const ValueKey('trace-chart')), findsNothing);
      expect(find.byKey(const ValueKey('trace-list')), findsOneWidget);
      final october = tester
          .getTopLeft(find.text('October 2026 (so far)').first)
          .dy;
      final september = tester.getTopLeft(find.text('September 2026').first).dy;
      expect(october, lessThan(september));

      await tester.tap(find.byKey(const ValueKey('trace-list-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('trace-chart')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the share kept, month by month', (tester) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      // July: 2,000.00 in, 100.00 out: 95.0% kept. October: nothing in.
      expect(find.text('95.0%'), findsOneWidget);
      expect(find.text('nothing received'), findsWidgets);
      await disposeEnv(tester, env);
    });

    testWidgets('a category over time: a hint first, then its peaks', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      expect(find.byKey(const ValueKey('trend-category-hint')), findsOneWidget);

      final food = find.widgetWithText(ChoiceChip, 'Food');
      await tester.ensureVisible(food);
      await tester.pump();
      await tester.tap(food);
      await settle(tester);
      expect(find.byKey(const ValueKey('trend-category-hint')), findsNothing);
      // Two charts now: money in and out, and Food.
      expect(find.byKey(const ValueKey('trace-chart')), findsNWidgets(2));

      final none = find.byKey(const ValueKey('trend-category-none'));
      await tester.ensureVisible(none);
      await tester.pump();
      await tester.tap(none);
      await settle(tester);
      expect(find.byKey(const ValueKey('trend-category-hint')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('what moved most against the months before it', (tester) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      final note = find.byKey(const ValueKey('movers-note'));
      await tester.ensureVisible(note);
      await tester.pump();
      expect(
        tester.widget<Text>(note).data,
        'September against the 2 months before it.',
      );
      // Food 200.00 against 100.00 usually; Rent 100.00 against 150.00.
      expect(find.text(r'+$100.00'), findsOneWidget);
      expect(find.text(r'-$50.00'), findsOneWidget);
      expect(find.text(r'$200.00 against $100.00 usually'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('how this month has run so far', (tester) async {
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      final label = find.text('THIS MONTH SO FAR');
      await tester.ensureVisible(label);
      await tester.pump();

      expect(find.text('Biggest expense'), findsOneWidget);
      expect(find.text(r'-$25.00'), findsOneWidget);
      expect(find.text('Busiest day'), findsOneWidget);
      expect(find.text(r'-$30.00'), findsOneWidget, reason: 'Oct 5: 25 and 5');
      expect(
        find.text(r'-$2.67'),
        findsOneWidget,
        reason: '40.00 over 15 days',
      );
      // Spent on the 2nd and the 5th: 13 quiet days of 15, the last 10 in a row.
      expect(find.text('13'), findsOneWidget);
      expect(find.text('10 days'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('one month says it needs a second', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 1000, d(2026, 10, 2));
      await openTrendsPage(tester, env);
      expect(find.byKey(const ValueKey('trends-thin')), findsOneWidget);
      expect(find.byKey(const ValueKey('movers-note')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('nothing logged: a flat line, not an empty page', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openTrendsPage(tester, env);
      expect(
        find.text('Flat line. Log a few transactions to see a trace.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trace-month-0')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a failed read says so and offers Try again', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            trendTotalsProvider(6).overrideWith(
              (ref) => throw StateError('the database could not be read'),
            ),
          ],
          child: MaterialApp(
            theme: lightTheme(),
            darkTheme: darkTheme(),
            home: const TrendsScreen(),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Could not load your trends.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await withHistory(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openTrendsPage(tester, env);
      await tester.tap(find.byKey(const ValueKey('trace-month-4')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('trace-list-toggle')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('trace-list-toggle')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('each month is a labelled button for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await withHistory(tester);
      await openTrendsPage(tester, env);
      expect(
        find.bySemanticsLabel(
          r'September 2026, received $2,000.00, spent $300.00',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^October 2026, so far, received')),
        findsOneWidget,
      );
      handle.dispose();
      await disposeEnv(tester, env);
    });
  });

  group('from the spending chart', () {
    testWidgets('See trend opens Trends on that category', (tester) async {
      final env = await withHistory(tester); // October: Rent 25.00, Food 15.00
      await openHome(tester, env);

      await tester.tap(find.byKey(const ValueKey('spectrum-bar-0')));
      await settle(tester);
      final trend = find.byKey(const ValueKey('spectrum-trend'));
      await tester.ensureVisible(trend);
      await tester.pump();
      await tester.tap(trend);
      await settle(tester);

      expect(find.byType(TrendsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('trend-category-hint')), findsNothing);
      expect(find.byKey(const ValueKey('trace-chart')), findsNWidgets(2));
      await disposeEnv(tester, env);
    });

    testWidgets('the Rest peak has no trend, only its transactions', (
      tester,
    ) async {
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
          d(2026, 10, day++),
          category: name,
        );
      }
      await openHome(tester, env);
      await tester.tap(find.byKey(const ValueKey('spectrum-bar-5')));
      await settle(tester);
      expect(find.byKey(const ValueKey('spectrum-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('spectrum-trend')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('the notice slot at the top of Home', () {
    testWidgets('a backup reminder sits above everything else', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {'last_backup_at': d(2026, 9, 1).toUtc().toIso8601String()},
      );
      await openHome(tester, env);
      final card = tester.getRect(
        find.byKey(const ValueKey('backup-reminder')),
      );
      final name = tester.getRect(find.text('HEISENBUDGET'));
      final balance = tester.getRect(find.byKey(const ValueKey('balance')));
      expect(card.bottom, lessThanOrEqualTo(name.top));
      expect(name.top, lessThan(balance.top));
      await disposeEnv(tester, env);
    });

    testWidgets('with no notice, Home starts with its name', (tester) async {
      final env = await createEnv(tester);
      await openHome(tester, env);
      expect(find.byKey(const ValueKey('backup-reminder')), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('HEISENBUDGET'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });
}
