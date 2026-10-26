import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/search.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/providers/history_providers.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

/// Types into the search box and waits out the typing pause.
Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('search-field')), text);
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('search-button')));
  await settle(tester);
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HistoryScreen)));

/// How many History rows are showing.
int rows() => find
    .byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('tx-');
    })
    .evaluate()
    .length;

Future<TestEnv> seeded(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  final env = await createEnv(tester, prefs: prefs);
  await addExpense(tester, env, 450, d(2026, 10, 5), note: 'Iced Coffee');
  await addExpense(tester, env, 1250, d(2026, 10, 6), note: 'Lunch with Sam');
  await addExpense(
    tester,
    env,
    4999,
    d(2026, 10, 7),
    category: 'Shopping',
    note: 'Shirt',
  );
  await addExpense(tester, env, 450, d(2026, 10, 8), category: 'Rent');
  await addIncome(tester, env, 500000, d(2026, 10, 1));
  return env;
}

void main() {
  testWidgets('the search icon opens a focused box and closes it again', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');

    expect(find.byKey(const ValueKey('search-field')), findsNothing);
    expect(find.byTooltip('Search'), findsOneWidget);
    await openSearch(tester);
    expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
    expect(find.byTooltip('Close search'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search-field')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('finds by note, case-insensitively, and shows a results line', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    expect(rows(), 5);

    await openSearch(tester);
    await typeQuery(tester, 'COFFEE');
    expect(rows(), 1);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('search-summary'))).data,
      '1 result · net -\$4.50',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('finds by category name and by amount', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);

    await typeQuery(tester, 'shop');
    expect(rows(), 1);

    await typeQuery(tester, '4.50');
    expect(rows(), 2, reason: 'two 4.50 rows');

    await typeQuery(tester, '12');
    expect(rows(), 1, reason: '12.50');

    await typeQuery(tester, '5000');
    expect(rows(), 1, reason: 'the 5,000.00 salary');
    await disposeEnv(tester, env);
  });

  testWidgets('several words must all match', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);

    await typeQuery(tester, 'coffee 4');
    expect(rows(), 1);
    await typeQuery(tester, 'coffee 9');
    expect(rows(), 0);
    await disposeEnv(tester, env);
  });

  testWidgets('the summary counts and totals what is shown', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);

    await typeQuery(tester, '4.50');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('search-summary'))).data,
      '2 results · net -\$9.00',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('matching text is emphasised in the row', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coff');

    final marked = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((r) {
          final spans = <TextSpan>[];
          r.text.visitChildren((s) {
            if (s is TextSpan) spans.add(s);
            return true;
          });
          return spans;
        })
        .where(
          (s) => s.style?.fontWeight == FontWeight.w700 && s.text == 'Coff',
        );
    expect(marked, isNotEmpty);
    await disposeEnv(tester, env);
  });

  testWidgets('no matches says so, and Clear search restores the list', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'zzz');

    expect(find.textContaining('Nothing matches “zzz”.'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-summary')), findsNothing);
    await tester.tap(find.text('Clear search'));
    await settle(tester);
    expect(rows(), 5);
    await disposeEnv(tester, env);
  });

  testWidgets('with Lab flavor off the no-match text is plain', (tester) async {
    final env = await seeded(tester, prefs: {'lab_flavor': false});
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'zzz');
    expect(find.text('No matches for “zzz”.'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('the clear button empties the box and the list returns', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coffee');
    expect(rows(), 1);

    await tester.tap(find.byKey(const ValueKey('search-clear')));
    await settle(tester);
    expect(rows(), 5);
    expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-clear')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('closing the search drops the query', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coffee');

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await settle(tester);
    expect(rows(), 5);
    expect(containerOf(tester).read(historyFilterProvider).query, '');
    await disposeEnv(tester, env);
  });

  testWidgets('the query is kept when you switch tabs and come back', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coffee');

    await goToTab(tester, 'Settings');
    await goToTab(tester, 'History');
    expect(rows(), 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-field')))
          .controller!
          .text,
      'coffee',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('a search chip appears and removing it clears the search', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coffee');

    expect(find.byKey(const ValueKey('active-search')), findsOneWidget);
    expect(find.text('Search: coffee'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('active-search')),
        matching: find.byTooltip('Remove search'),
      ),
    );
    await settle(tester);
    expect(rows(), 5);
    expect(find.byKey(const ValueKey('active-search')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-field')))
          .controller!
          .text,
      '',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('search is not counted as a filter and survives Clear filters', (
    tester,
  ) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, '4.50');
    expect(find.text('Filter'), findsOneWidget, reason: 'no "Filter · 1"');

    final container = containerOf(tester);
    final notifier = container.read(historyFilterProvider.notifier);
    notifier.setType(null);
    notifier.clear();
    await settle(tester);
    expect(container.read(historyFilterProvider).query, '4.50');
    expect(rows(), 2);
    await disposeEnv(tester, env);
  });

  testWidgets('it narrows the filtered list, never widens it', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, '4.50');
    expect(rows(), 2);

    // Only income: the two 4.50 expenses no longer match.
    containerOf(tester)
        .read(historyFilterProvider.notifier)
        .setType(TransactionType.income);
    await settle(tester);
    expect(rows(), 0);
    expect(find.textContaining('Nothing matches'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('a very long query is cut at the limit', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('search-field')),
      'a' * 300,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('search-field')))
          .controller!
          .text
          .length,
      maxSearchLength,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('typing hits the list only after a pause', (tester) async {
    final env = await seeded(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);

    await tester.enterText(
      find.byKey(const ValueKey('search-field')),
      'coffee',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(containerOf(tester).read(historyFilterProvider).query, '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(containerOf(tester).read(historyFilterProvider).query, 'coffee');
    await disposeEnv(tester, env);
  });

  testWidgets('fits at 200% text on a small screen', (tester) async {
    final env = await seeded(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'History');
    await openSearch(tester);
    await typeQuery(tester, 'coffee');
    expect(tester.takeException(), isNull);
    await typeQuery(tester, 'zzz');
    expect(tester.takeException(), isNull);
    await disposeEnv(tester, env);
  });
}
