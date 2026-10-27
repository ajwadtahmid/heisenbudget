import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';
import 'package:heisenbudget/providers/backup_providers.dart';

import 'test_helpers.dart';

import 'package:heisenbudget/providers/budget_history_providers.dart';

/// Stands in for the share sheet and the file picker.
class FakeFileExchange extends FileExchange {
  FakeFileExchange({
    this.toPick,
    this.shareFails = false,
    this.saveCancelled = false,
  });

  Uint8List? toPick;
  bool shareFails;

  /// The person closes the save dialog without choosing a folder.
  bool saveCancelled;
  final saved = <({String name, String mime, Uint8List bytes})>[];
  final shared = <({String name, String mime, Uint8List bytes})>[];

  @override
  Future<void> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    if (shareFails) throw StateError('no share target');
    shared.add((name: fileName, mime: mimeType, bytes: bytes));
  }

  @override
  Future<bool> saveFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (saveCancelled) return false;
    saved.add((name: fileName, mime: mimeType, bytes: bytes));
    return true;
  }

  @override
  Future<Uint8List?> pickFile() async => toPick;

  int sweeps = 0;

  @override
  Future<void> clearOldExports() async => sweeps++;
}

Uint8List backupBytes() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'app': 'heisenbudget',
      'format': 1,
      'exportedAt': '2026-10-25T12:00:00Z',
      'settings': {'currency': 'BDT', 'labFlavor': false},
      'categories': [
        {'id': 7, 'name': 'Tea', 'type': 'expense', 'icon': 'restaurant'},
        {'id': 8, 'name': 'Pay', 'type': 'income', 'icon': 'salary'},
      ],
      'transactions': [
        {
          'id': 1,
          'amountCents': 4500,
          'type': 'expense',
          'date': '2026-10-05',
          'categoryId': 7,
          'note': 'From backup',
          'createdAt': '2026-10-05T08:00:00Z',
          'updatedAt': '2026-10-05T08:00:00Z',
        },
      ],
    }),
  ),
);

Future<void> openSettings(
  WidgetTester tester,
  TestEnv env,
  FakeFileExchange exchange,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides,
        fileExchangeProvider.overrideWithValue(exchange),
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

Future<void> tapTile(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('Back up shares a dated JSON file that restores cleanly', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Lunch');
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-backup');

    expect(exchange.shared, hasLength(1));
    final file = exchange.shared.single;
    expect(file.name, 'heisenbudget-backup-2026-10-15.json');
    expect(file.mime, 'application/json');
    final data = BackupData.parse(file.bytes);
    expect(data.transactions.single.note, 'Lunch');
    expect(data.settings.currency, 'USD');
    await disposeEnv(tester, env);
  });

  testWidgets('Export to CSV shares the transactions', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Lunch');
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-csv');

    final file = exchange.shared.single;
    expect(file.name, 'heisenbudget-transactions-2026-10-15.csv');
    expect(file.mime, 'text/csv');
    expect(
      utf8.decode(file.bytes),
      contains('2026-10-05,Expense,Food,,12.50,Lunch'),
    );
    await disposeEnv(tester, env);
  });

  testWidgets('Export to CSV with nothing logged says so and shares nothing', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-csv');

    expect(exchange.shared, isEmpty);
    expect(find.text('No transactions to export yet.'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('a failing share sheet shows a calm message, not a crash', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange(shareFails: true);
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-backup');

    expect(
      find.text('Something went wrong. Nothing was changed.'),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('Restore asks first, then replaces data and settings', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(
      find.textContaining('1 transaction and 2 categories'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    // Nothing changed yet.
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );

    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await settle(tester);

    final saved = await savedTransactions(tester, env);
    expect(saved.single.transaction.note, 'From backup');
    expect(saved.single.category.name, 'Tea');
    expect(env.prefs.getString('currency_code'), 'BDT');
    expect(find.text('Backup restored.'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('cancelling the restore dialog changes nothing', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');
    await tester.tap(find.byKey(const ValueKey('restore-cancel')));
    await settle(tester);

    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );
    expect(env.prefs.getString('currency_code'), 'USD');
    expect(find.text('Backup restored.'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('a file that is not a backup is refused with a clear message', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(
      toPick: Uint8List.fromList(utf8.encode('{"hello": "world"}')),
    );
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(
      find.text('That file is not a Heisenbudget backup.'),
      findsOneWidget,
    );
    expect(find.text('Restore this backup?'), findsNothing);
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('closing the file picker does nothing', (tester) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(find.text('Restore this backup?'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('restoring forgets History filters that held old ids', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    container.listen(budgetHistoryFilterProvider, (_, _) {});
    container.listen(historyModeProvider, (_, _) {});
    container.read(budgetHistoryFilterProvider.notifier).setTargets({7, 99});
    container.read(historyModeProvider.notifier).set(HistoryMode.budgets);

    await tapTile(tester, 'restore-backup');
    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await settle(tester);

    expect(container.read(budgetHistoryFilterProvider).hasFilters, isFalse);
    expect(container.read(historyModeProvider), HistoryMode.transactions);
    await disposeEnv(tester, env);
  });

  testWidgets('Restore offers a backup of what is here first, then asks '
      'again', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');
    expect(find.text('Restore this backup?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-backup-first')));
    await settle(tester);

    // The current data was shared as a backup file...
    expect(exchange.shared, hasLength(1));
    expect(exchange.shared.single.name, startsWith('heisenbudget-backup-'));
    // ...nothing was replaced yet, and the question is asked again.
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );
    expect(find.text('Restore this backup?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await settle(tester);
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'From backup',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('old exports are swept when the app starts and when it returns', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);
    expect(exchange.sweeps, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(exchange.sweeps, 1, reason: 'leaving the app does not sweep');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(exchange.sweeps, 2);
    await disposeEnv(tester, env);
  });

  group('save to a folder', () {
    testWidgets('writes the backup where the dialog points and counts it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Lunch');
      final exchange = FakeFileExchange();
      await openSettings(tester, env, exchange);
      expect(env.prefs.getString('last_backup_at'), isNull);

      await tapTile(tester, 'save-backup-folder');

      final file = exchange.saved.single;
      expect(file.name, 'heisenbudget-backup-2026-10-15.json');
      expect(file.mime, 'application/json');
      expect(BackupData.parse(file.bytes).transactions.single.note, 'Lunch');
      expect(exchange.shared, isEmpty, reason: 'not the share sheet');
      expect(find.text('Backup saved.'), findsOneWidget);
      expect(env.prefs.getString('last_backup_at'), isNotNull);
      await disposeEnv(tester, env);
    });

    testWidgets('closing the dialog saves nothing and records nothing', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final exchange = FakeFileExchange(saveCancelled: true);
      await openSettings(tester, env, exchange);

      await tapTile(tester, 'save-backup-folder');

      expect(exchange.saved, isEmpty);
      expect(find.text('Backup saved.'), findsNothing);
      expect(env.prefs.getString('last_backup_at'), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('backup reminder', () {
    // Today is Oct 15, 2026; Sep 1 is 44 days back.
    final stale = {
      'last_backup_at': DateTime(2026, 9, 1).toUtc().toIso8601String(),
    };

    Future<void> openHome(
      WidgetTester tester,
      TestEnv env,
      FakeFileExchange exchange,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            fileExchangeProvider.overrideWithValue(exchange),
          ],
          child: const HeisenbudgetApp(),
        ),
      );
      await settle(tester);
    }

    Finder card() => find.byKey(const ValueKey('backup-reminder'));

    Future<void> tapCard(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await settle(tester);
    }

    testWidgets('shows how old the last backup is, and Back up now makes one', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: stale);
      final exchange = FakeFileExchange();
      await openHome(tester, env, exchange);
      expect(card(), findsOneWidget);
      expect(find.text('Time for a backup'), findsOneWidget);
      expect(find.text('Your last backup is 44 days old.'), findsOneWidget);

      await tapCard(tester, 'reminder-backup-now');

      expect(exchange.shared, hasLength(1));
      expect(card(), findsNothing, reason: 'it is recent now');
      await disposeEnv(tester, env);
    });

    testWidgets('never backed up: asks only once there is enough to lose', (
      tester,
    ) async {
      final env = await createEnv(tester);
      for (var i = 0; i < 9; i++) {
        await addExpense(tester, env, 100 + i, DateTime(2026, 10, 1 + i));
      }
      await openHome(tester, env, FakeFileExchange());
      expect(card(), findsNothing, reason: 'nine transactions');

      await addExpense(tester, env, 999, DateTime(2026, 10, 12));
      await settle(tester);
      expect(card(), findsOneWidget, reason: 'ten');
      expect(find.text('Back up your data'), findsOneWidget);
      expect(find.textContaining('not saved a backup yet'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a recent backup shows nothing', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {
          'last_backup_at': DateTime(2026, 10, 10).toUtc().toIso8601String(),
        },
      );
      await openHome(tester, env, FakeFileExchange());
      expect(card(), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('Remind me later hides it for a week', (tester) async {
      final env = await createEnv(tester, prefs: stale);
      await openHome(tester, env, FakeFileExchange());

      await tapCard(tester, 'reminder-later');

      expect(card(), findsNothing);
      expect(env.prefs.getString('backup_snoozed_until'), '2026-10-22');
      expect(env.prefs.getBool('backup_reminders'), isNull, reason: 'still on');
      await disposeEnv(tester, env);
    });

    testWidgets(
      'Stop reminding me turns them off, and Settings turns them on',
      (tester) async {
        final env = await createEnv(tester, prefs: stale);
        final exchange = FakeFileExchange();
        await openHome(tester, env, exchange);

        await tapCard(tester, 'reminder-off');
        expect(card(), findsNothing);
        expect(env.prefs.getBool('backup_reminders'), isFalse);
        expect(
          find.textContaining('turn them on again in Settings'),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Settings'),
          ),
        );
        await settle(tester);
        final toggle = find.byKey(const ValueKey('backup-reminders'));
        await tester.ensureVisible(toggle);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

        await tester.tap(toggle);
        await settle(tester);
        expect(env.prefs.getBool('backup_reminders'), isTrue);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Home'),
          ),
        );
        await settle(tester);
        expect(card(), findsOneWidget, reason: 'the backup is still old');
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a failing share keeps the card and says so', (tester) async {
      final env = await createEnv(tester, prefs: stale);
      final exchange = FakeFileExchange(shareFails: true);
      await openHome(tester, env, exchange);

      await tapCard(tester, 'reminder-backup-now');

      expect(
        find.text('Something went wrong. No backup was made.'),
        findsOneWidget,
      );
      expect(card(), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the card fits at 200% text on a small phone', (tester) async {
      final env = await createEnv(tester, prefs: stale);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, env, FakeFileExchange());
      expect(card(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });
}
