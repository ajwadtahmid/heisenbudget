import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/shortcuts/shortcut_service.dart';
import 'package:heisenbudget/domain/quick_add.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

void main() {
  group('requestFromShortcut', () {
    test('the two type shortcuts', () {
      expect(
        requestFromShortcut('add_expense'),
        const QuickAddRequest.type(TransactionType.expense),
      );
      expect(
        requestFromShortcut('add_income'),
        const QuickAddRequest.type(TransactionType.income),
      );
    });

    test('a favorite shortcut carries its id', () {
      expect(
        requestFromShortcut('favorite:12'),
        const QuickAddRequest.favorite(12),
      );
    });

    test('anything it does not know is ignored', () {
      for (final odd in [
        '',
        'add_transfer',
        'favorite:',
        'favorite:x',
        'favorite:0',
        'favorite:-3',
        'favorite:1:2',
        'ADD_EXPENSE',
      ]) {
        expect(requestFromShortcut(odd), isNull, reason: '"$odd"');
      }
    });

    test('the identifiers the launcher stores never change', () {
      // These strings live on users' home screens; renaming one orphans it.
      expect(shortcutAddExpense, 'add_expense');
      expect(shortcutAddIncome, 'add_income');
      expect(shortcutFavoritePrefix, 'favorite:');
    });
  });

  group('buildShortcuts', () {
    test('always offers Add expense and Add income', () {
      final items = buildShortcuts();
      expect(items.map((s) => s.type), ['add_expense', 'add_income']);
      expect(items.map((s) => s.title), ['Add expense', 'Add income']);
    });

    test('adds the first favorite, which opens the Add sheet', () {
      final items = buildShortcuts(
        topFavoriteId: 7,
        topFavoriteLabel: 'Coffee',
      );
      expect(items, hasLength(3));
      expect(items.last.type, 'favorite:7');
      expect(items.last.title, 'Add Coffee');
      expect(
        requestFromShortcut(items.last.type),
        const QuickAddRequest.favorite(7),
      );
    });

    test('every shortcut maps back to a request and names a bundled icon', () {
      for (final s in buildShortcuts(topFavoriteId: 1, topFavoriteLabel: 'x')) {
        expect(requestFromShortcut(s.type), isNotNull, reason: s.type);
        expect(s.icon, startsWith('ic_shortcut_'));
      }
    });
  });
}
