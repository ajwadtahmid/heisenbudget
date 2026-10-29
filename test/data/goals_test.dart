import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/category_icons.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/goal_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List bytesOf(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// A small valid backup with two goals and some entries.
Map<String, Object?> backupWithGoals() => {
  'app': 'heisenbudget',
  'format': 1,
  'exportedAt': '2026-10-25T12:00:00Z',
  'settings': {'currency': 'USD'},
  'categories': <Object?>[
    {'id': 1, 'name': 'Food', 'type': 'expense', 'icon': 'restaurant'},
    {'id': 2, 'name': 'Salary', 'type': 'income', 'icon': 'salary'},
  ],
  'transactions': <Object?>[],
  'savingsGoals': <Object?>[
    {
      'id': 4,
      'name': 'Laptop',
      'targetCents': 100000,
      'targetDate': '2027-03-01',
      'icon': 'computer',
      'sortOrder': 1,
      'createdAt': '2026-10-05T08:00:00Z',
    },
    {
      'id': 7,
      'name': 'Trip',
      'targetCents': 60000,
      'targetDate': null,
      'icon': 'savings',
      'sortOrder': 0,
      'createdAt': '2026-10-06T08:00:00Z',
    },
  ],
  'goalEntries': <Object?>[
    {
      'id': 1,
      'goalId': 4,
      'amountCents': 30000,
      'date': '2026-10-10',
      'createdAt': '2026-10-10T08:00:00Z',
    },
    {
      'id': 2,
      'goalId': 4,
      'amountCents': -5000,
      'date': '2026-10-12',
      'createdAt': '2026-10-12T08:00:00Z',
    },
    {
      'id': 3,
      'goalId': 7,
      'amountCents': 1000,
      'date': '2026-10-12',
      'createdAt': '2026-10-12T08:00:00Z',
    },
  ],
};

Map<String, Object?> goalOf(Map<String, Object?> b, [int i = 0]) =>
    (b['savingsGoals']! as List)[i] as Map<String, Object?>;
Map<String, Object?> entryOf(Map<String, Object?> b, [int i = 0]) =>
    (b['goalEntries']! as List)[i] as Map<String, Object?>;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late GoalRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = GoalRepository(db);
  });
  tearDown(() => db.close());

  GoalInput input({
    String name = 'Laptop',
    int target = 100000,
    DateTime? date,
    String icon = 'savings',
  }) =>
      GoalInput(name: name, targetCents: target, targetDate: date, icon: icon);

  group('GoalRepository', () {
    test('adds goals at the end of the list, trimming the name', () async {
      await repo.add(input(name: '  Laptop  '));
      await repo.add(input(name: 'Trip', date: d(2027, 3, 1)));
      final goals = await repo.watchGoals().first;
      expect(goals.map((g) => g.name), ['Laptop', 'Trip']);
      expect(goals.map((g) => g.sortOrder), [0, 1]);
      expect(goals.first.targetDate, isNull);
      expect(goals.last.targetDate, '2027-03-01');
    });

    test('the default icon is the one the column defaults to', () async {
      await db
          .into(db.savingsGoals)
          .insert(
            SavingsGoalsCompanion.insert(
              name: 'x',
              targetCents: 1,
              createdAt: d(2026, 10, 27),
            ),
          );
      expect(
        (await db.select(db.savingsGoals).getSingle()).icon,
        defaultGoalIconKey,
      );
    });

    test('rejects a bad name, target, date or icon', () async {
      expect(() => repo.add(input(name: '   ')), throwsArgumentError);
      expect(
        () => repo.add(input(name: 'x' * (maxGoalNameLength + 1))),
        throwsArgumentError,
      );
      await repo.add(input(name: 'x' * maxGoalNameLength));
      expect(() => repo.add(input(target: 0)), throwsRangeError);
      expect(
        () => repo.add(input(target: maxAmountCents + 1)),
        throwsRangeError,
      );
      await repo.add(input(target: maxAmountCents));
      expect(() => repo.add(input(date: d(1800, 1, 1))), throwsArgumentError);
      expect(() => repo.add(input(date: d(3000, 1, 1))), throwsArgumentError);
      expect(() => repo.add(input(icon: ' ')), throwsArgumentError);
    });

    test(
      'allows $maxActiveGoals goals at a time; a reached one makes room',
      () async {
        final ids = <int>[];
        for (var i = 0; i < maxActiveGoals; i++) {
          ids.add(await repo.add(input(name: 'Goal $i')));
        }
        expect(() => repo.add(input()), throwsA(isA<GoalLimitException>()));

        await repo.addEntry(ids.first, cents: 100000, date: d(2026, 10, 27));
        await repo.add(
          input(name: 'One more'),
        ); // the reached one no longer counts
        expect(() => repo.add(input()), throwsA(isA<GoalLimitException>()));
      },
    );

    test('update changes the goal and keeps its entries', () async {
      final id = await repo.add(input());
      await repo.addEntry(id, cents: 5000, date: d(2026, 10, 27));
      await repo.update(
        id,
        input(name: 'Phone', target: 70000, date: d(2027, 1, 1), icon: 'phone'),
      );
      final g = (await repo.getById(id))!;
      expect(g.name, 'Phone');
      expect(g.targetCents, 70000);
      expect(g.targetDate, '2027-01-01');
      expect(g.icon, 'phone');
      expect(await repo.savedIn(id), 5000);
      expect(() => repo.update(id, input(target: 0)), throwsRangeError);
    });

    test('deleting a goal deletes its entries and no one else\'s', () async {
      final a = await repo.add(input(name: 'A'));
      final b = await repo.add(input(name: 'B'));
      await repo.addEntry(a, cents: 100, date: d(2026, 10, 1));
      await repo.addEntry(b, cents: 200, date: d(2026, 10, 1));
      await repo.delete(a);
      expect((await repo.watchGoals().first).map((g) => g.name), ['B']);
      final entries = await repo.watchEntries().first;
      expect(entries.map((e) => e.amountCents), [200]);
    });

    test('reorder puts the goals in the given order', () async {
      final a = await repo.add(input(name: 'A'));
      final b = await repo.add(input(name: 'B'));
      final c = await repo.add(input(name: 'C'));
      await repo.reorder([c, a, b]);
      expect((await repo.watchGoals().first).map((g) => g.name), [
        'C',
        'A',
        'B',
      ]);
    });

    test('entries add up, in date order, and take money out', () async {
      final id = await repo.add(input());
      await repo.addEntry(id, cents: 5000, date: d(2026, 10, 20));
      await repo.addEntry(id, cents: 2000, date: d(2026, 10, 5));
      await repo.addEntry(id, cents: -1500, date: d(2026, 10, 25));
      expect(await repo.savedIn(id), 5500);
      final entries = await repo.watchEntries().first;
      expect(entries.map((e) => e.date), [
        '2026-10-05',
        '2026-10-20',
        '2026-10-25',
      ]);
    });

    test('an entry keeps only the day', () async {
      final id = await repo.add(input());
      await repo.addEntry(id, cents: 100, date: DateTime(2026, 10, 5, 23, 59));
      expect((await repo.watchEntries().first).single.date, '2026-10-05');
    });

    test(
      'rejects a zero or enormous entry, a bad date, a missing goal',
      () async {
        final id = await repo.add(input());
        expect(
          () => repo.addEntry(id, cents: 0, date: d(2026, 10, 1)),
          throwsRangeError,
        );
        expect(
          () => repo.addEntry(
            id,
            cents: maxAmountCents + 1,
            date: d(2026, 10, 1),
          ),
          throwsRangeError,
        );
        expect(
          () => repo.addEntry(id, cents: 1, date: d(1800, 1, 1)),
          throwsArgumentError,
        );
        expect(
          () => repo.addEntry(99, cents: 1, date: d(2026, 10, 1)),
          throwsArgumentError,
        );
      },
    );

    test('a goal cannot be taken below zero', () async {
      final id = await repo.add(input());
      await repo.addEntry(id, cents: 3000, date: d(2026, 10, 1));
      await expectLater(
        repo.addEntry(id, cents: -3001, date: d(2026, 10, 2)),
        throwsA(isA<GoalBelowZeroException>()),
      );
      await repo.addEntry(id, cents: -3000, date: d(2026, 10, 2));
      expect(await repo.savedIn(id), 0);
      expect(await repo.watchEntries().first, hasLength(2));
    });

    test('removing an entry that later ones draw on is refused', () async {
      final id = await repo.add(input());
      final deposit = await repo.addEntry(
        id,
        cents: 3000,
        date: d(2026, 10, 1),
      );
      final taking = await repo.addEntry(
        id,
        cents: -2000,
        date: d(2026, 10, 2),
      );
      await expectLater(
        repo.deleteEntry(deposit),
        throwsA(isA<GoalBelowZeroException>()),
      );
      await repo.deleteEntry(taking);
      await repo.deleteEntry(deposit);
      expect(await repo.savedIn(id), 0);
      await repo.deleteEntry(12345); // already gone: nothing happens
    });

    test('goals do not touch transactions or categories', () async {
      final before = await db.select(db.categories).get();
      final id = await repo.add(input());
      await repo.addEntry(id, cents: 100, date: d(2026, 10, 1));
      expect(await db.select(db.transactions).get(), isEmpty);
      expect((await db.select(db.categories).get()).length, before.length);
    });
  });

  group('goals in backups', () {
    test('reads goals and their entries', () {
      final data = BackupData.parse(bytesOf(backupWithGoals()));
      expect(data.savingsGoals.map((g) => g.name), ['Laptop', 'Trip']);
      expect(data.savingsGoals.first.targetDate, '2027-03-01');
      expect(data.savingsGoals.last.targetDate, isNull);
      expect(data.goalEntries, hasLength(3));
      expect(data.goalEntries[1].amountCents, -5000);
    });

    test('a backup from before goals still restores, with none', () {
      final b = backupWithGoals()
        ..remove('savingsGoals')
        ..remove('goalEntries');
      final data = BackupData.parse(bytesOf(b));
      expect(data.savingsGoals, isEmpty);
      expect(data.goalEntries, isEmpty);
    });

    test('goals without entries are fine; a missing icon is the default', () {
      final b = backupWithGoals()..remove('goalEntries');
      goalOf(b).remove('icon');
      final data = BackupData.parse(bytesOf(b));
      expect(data.goalEntries, isEmpty);
      expect(data.savingsGoals.first.icon, defaultGoalIconKey);
    });

    final bad = <String, void Function(Map<String, Object?>)>{
      'goals that are not a list': (b) => b['savingsGoals'] = 'x',
      'a goal that is not an object': (b) =>
          (b['savingsGoals']! as List)[0] = 3,
      'a goal with no id': (b) => goalOf(b).remove('id'),
      'a repeated goal id': (b) => goalOf(b, 1)['id'] = 4,
      'a blank goal name': (b) => goalOf(b)['name'] = '  ',
      'a goal name that is too long': (b) =>
          goalOf(b)['name'] = 'x' * (maxGoalNameLength + 1),
      'a target of zero': (b) => goalOf(b)['targetCents'] = 0,
      'a target that is too big': (b) =>
          goalOf(b)['targetCents'] = maxAmountCents + 1,
      'a target that is not a number': (b) => goalOf(b)['targetCents'] = '5',
      'a target date that is not real': (b) =>
          goalOf(b)['targetDate'] = '2027-02-31',
      'a target date that is not text': (b) => goalOf(b)['targetDate'] = 5,
      'a goal with no timestamp': (b) => goalOf(b).remove('createdAt'),
      'entries that are not a list': (b) => b['goalEntries'] = {},
      'an entry for a goal that does not exist': (b) =>
          entryOf(b)['goalId'] = 99,
      'an entry with no id': (b) => entryOf(b).remove('id'),
      'a repeated entry id': (b) => entryOf(b, 1)['id'] = 1,
      'an entry of zero': (b) => entryOf(b)['amountCents'] = 0,
      'an entry that is too big': (b) =>
          entryOf(b)['amountCents'] = maxAmountCents + 1,
      'an entry that is not a number': (b) => entryOf(b)['amountCents'] = 1.5,
      'an entry date that is not real': (b) =>
          entryOf(b)['date'] = '2026-13-01',
      'an entry with no timestamp': (b) => entryOf(b).remove('createdAt'),
      'a goal holding less than nothing': (b) =>
          entryOf(b, 1)['amountCents'] = -30001,
    };
    for (final MapEntry(key: why, value: damage) in bad.entries) {
      test('rejects: $why', () {
        final b = backupWithGoals();
        damage(b);
        expect(
          () => BackupData.parse(bytesOf(b)),
          throwsA(isA<BackupFormatException>()),
        );
      });
    }

    test('accepts a goal that holds exactly nothing', () {
      final b = backupWithGoals();
      entryOf(b, 1)['amountCents'] = -30000;
      expect(BackupData.parse(bytesOf(b)).goalEntries, hasLength(3));
    });

    test('accepts the first and last days of the allowed years', () {
      final b = backupWithGoals();
      goalOf(b)['targetDate'] = '1900-01-01';
      entryOf(b)['date'] = '2999-12-31';
      expect(BackupData.parse(bytesOf(b)).savingsGoals, hasLength(2));
    });

    group('with a database', () {
      late SettingsRepository settings;
      late BackupService service;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        settings = SettingsRepository(
          await SharedPreferences.getInstance(),
          defaultCurrency: 'USD',
        );
        service = BackupService(db, settings);
      });

      test(
        'goals and entries survive a backup and restore, ids included',
        () async {
          await service.restore(BackupData.parse(bytesOf(backupWithGoals())));
          final snap = await service.snapshot(now: DateTime.utc(2026, 10, 25));
          final text = snap.encode();
          expect(snap.savingsGoals, hasLength(2));
          expect(snap.goalEntries, hasLength(3));

          // Wipe, then bring it back from the file's own text.
          await service.restore(BackupData.parse(bytesOf(_withoutGoals())));
          expect(await repo.watchGoals().first, isEmpty);
          expect(await repo.watchEntries().first, isEmpty);
          await service.restore(
            BackupData.parse(Uint8List.fromList(utf8.encode(text))),
          );

          final goals = await repo.watchGoals().first;
          expect(goals.map((g) => g.name), [
            'Trip',
            'Laptop',
          ], reason: 'by sortOrder');
          expect(goals.map((g) => g.id), containsAll([4, 7]));
          expect(await repo.savedIn(4), 25000);
          expect(await repo.savedIn(7), 1000);
          final laptop = goals.firstWhere((g) => g.id == 4);
          expect(laptop.icon, 'computer');
          expect(laptop.targetDate, '2027-03-01');
          expect(laptop.createdAt.toUtc(), DateTime.utc(2026, 10, 5, 8));
        },
      );

      test('restoring replaces the goals that were there', () async {
        final old = await repo.add(input(name: 'Old'));
        await repo.addEntry(old, cents: 500, date: d(2026, 10, 1));
        await service.restore(BackupData.parse(bytesOf(backupWithGoals())));
        final goals = await repo.watchGoals().first;
        expect(goals.map((g) => g.name), isNot(contains('Old')));
        expect(goals, hasLength(2));
        expect(await repo.watchEntries().first, hasLength(3));
      });

      test('a restore with no goals empties the goals', () async {
        final old = await repo.add(input(name: 'Old'));
        await repo.addEntry(old, cents: 500, date: d(2026, 10, 1));
        await service.restore(BackupData.parse(bytesOf(_withoutGoals())));
        expect(await repo.watchGoals().first, isEmpty);
        expect(await repo.watchEntries().first, isEmpty);
      });

      test(
        'new goals after a restore get ids above the restored ones',
        () async {
          await service.restore(BackupData.parse(bytesOf(backupWithGoals())));
          final id = await repo.add(input(name: 'New'));
          expect(id, greaterThan(7));
        },
      );

      test('Erase everything removes goals and entries', () async {
        final id = await repo.add(input());
        await repo.addEntry(id, cents: 500, date: d(2026, 10, 1));
        await service.eraseEverything();
        expect(await repo.watchGoals().first, isEmpty);
        expect(await repo.watchEntries().first, isEmpty);
      });

      test(
        'goals travel in the file; nothing else about them is stored',
        () async {
          final id = await repo.add(input(name: 'Laptop'));
          await repo.addEntry(id, cents: 500, date: d(2026, 10, 1));
          final text = (await service.snapshot(now: DateTime.utc(2026, 10, 25)))
              .encode();
          final json = jsonDecode(text) as Map<String, Object?>;
          expect(json.keys, containsAll(['savingsGoals', 'goalEntries']));
          expect(json['format'], 1, reason: 'the layout version is unchanged');
        },
      );
    });
  });
}

Map<String, Object?> _withoutGoals() {
  final b = backupWithGoals();
  b['savingsGoals'] = <Object?>[];
  b['goalEntries'] = <Object?>[];
  return b;
}
