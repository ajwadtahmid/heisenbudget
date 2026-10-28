import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heisenbudget/features/budgets/budgets_screen.dart';
import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/features/home/home_screen.dart';
import 'package:heisenbudget/features/settings/settings_screen.dart';
import 'package:heisenbudget/features/trends/insights_screen.dart';

import 'test_helpers.dart';

import 'package:intl/intl.dart';

int selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('shell shows 5 tabs and switches between them', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(selectedTab(tester), 0);

    Future<void> tapTab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await settle(tester);
    }

    await tapTab('Budgets');
    expect(selectedTab(tester), 1);
    await tapTab('Insights');
    expect(selectedTab(tester), 2);
    await tapTab('History');
    expect(selectedTab(tester), 3);
    await tapTab('Settings');
    expect(selectedTab(tester), 4);
    await tapTab('Home');
    expect(selectedTab(tester), 0);
    await disposeEnv(tester, env);
  });

  testWidgets('tabs stay alive while you switch away from them', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );
    await settle(tester);

    // Visited tabs stay built, so each keeps its own state; the others are
    // not built until they are opened.
    for (final type in [HomeScreen, SettingsScreen]) {
      expect(
        find.byType(type, skipOffstage: false),
        findsOneWidget,
        reason: '$type',
      );
    }
    for (final type in [BudgetsScreen, InsightsScreen, HistoryScreen]) {
      expect(
        find.byType(type, skipOffstage: false),
        findsNothing,
        reason: '$type is not built yet',
      );
    }
    await disposeEnv(tester, env);
  });

  group('the app is English only', () {
    testWidgets('dates and numbers read the same whatever the phone speaks', (
      tester,
    ) async {
      final env = await createEnv(tester);
      Intl.defaultLocale = 'de';
      tester.platformDispatcher.localesTestValue = const [Locale('bn', 'BD')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      expect(Intl.defaultLocale, 'en_US');
      expect(
        Localizations.localeOf(tester.element(find.byType(NavigationBar))),
        const Locale('en', 'US'),
      );
      expect(find.textContaining('Oct 1 – Oct 31, 2026'), findsWidgets);
      await disposeEnv(tester, env);
    });
  });
}
