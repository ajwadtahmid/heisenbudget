import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/features/home/home_screen.dart';
import 'package:heisenbudget/features/settings/settings_screen.dart';

import 'test_helpers.dart';

int selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('shell shows 3 tabs and switches between them', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
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

    await tapTab('History');
    expect(selectedTab(tester), 1);
    await tapTab('Settings');
    expect(selectedTab(tester), 2);
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

    // IndexedStack keeps every tab built, so each keeps its own state.
    for (final type in [HomeScreen, HistoryScreen, SettingsScreen]) {
      expect(
        find.byType(type, skipOffstage: false),
        findsOneWidget,
        reason: '$type',
      );
    }
    await disposeEnv(tester, env);
  });
}
