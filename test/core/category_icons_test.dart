import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/category_icons.dart';
import 'package:heisenbudget/data/database/seed.dart';

void main() {
  test('keys and labels are unique and non-empty', () {
    final keys = categoryIcons.map((o) => o.key).toList();
    final labels = categoryIcons.map((o) => o.label).toList();
    expect(keys.toSet().length, keys.length);
    expect(labels.toSet().length, labels.length);
    for (final o in categoryIcons) {
      expect(o.key, matches(RegExp(r'^[a-z]+$')));
      expect(o.label.trim(), isNotEmpty);
    }
  });

  test('there is a decent choice of icons', () {
    expect(categoryIcons.length, greaterThanOrEqualTo(250));
  });

  test('the default key exists and is the first option', () {
    expect(categoryIcons.first.key, defaultCategoryIconKey);
    expect(
      categoryIconFor(defaultCategoryIconKey).icon,
      Icons.category_outlined,
    );
  });

  test('lookup returns the matching option', () {
    expect(categoryIconFor('restaurant').icon, Icons.restaurant);
    expect(categoryIconFor('flight').label, 'Flight');
  });

  test('unknown and null keys fall back to the general icon', () {
    expect(categoryIconFor('does-not-exist').key, defaultCategoryIconKey);
    expect(categoryIconFor(null).key, defaultCategoryIconKey);
    expect(categoryIconFor('').key, defaultCategoryIconKey);
  });

  test('every default category uses an icon that exists', () {
    final keys = categoryIcons.map((o) => o.key).toSet();
    for (final (name, icon) in [
      ...defaultExpenseCategories,
      ...defaultIncomeCategories,
    ]) {
      expect(keys, contains(icon), reason: name);
    }
  });

  test('default categories have distinct icons apart from "Other"', () {
    final icons = [
      ...defaultExpenseCategories,
      ...defaultIncomeCategories,
    ].where((c) => c.$1 != 'Other').map((c) => c.$2).toList();
    expect(icons.toSet().length, icons.length);
  });

  group('sections', () {
    test('every icon belongs to a listed section, and none is empty', () {
      for (final o in categoryIcons) {
        expect(categoryIconGroups, contains(o.group), reason: o.key);
      }
      for (final group in categoryIconGroups) {
        expect(
          categoryIcons.where((o) => o.group == group),
          isNotEmpty,
          reason: group,
        );
      }
    });

    test('sections are in a stable order starting with General', () {
      expect(categoryIconGroups.first, 'General');
      expect(categoryIconGroups.toSet().length, categoryIconGroups.length);
    });
  });

  group('keys that earlier versions saved still exist', () {
    // These ship in the first release: removing one would blank a user's icon.
    const shipped = [
      'category',
      'restaurant',
      'fastfood',
      'cafe',
      'groceries',
      'bar',
      'cake',
      'home',
      'bills',
      'electricity',
      'water',
      'internet',
      'phone',
      'repairs',
      'laundry',
      'shopping',
      'cart',
      'clothes',
      'haircut',
      'spa',
      'medical',
      'fitness',
      'pets',
      'kids',
      'school',
      'bus',
      'car',
      'fuel',
      'train',
      'flight',
      'hotel',
      'beach',
      'movie',
      'games',
      'music',
      'book',
      'celebration',
      'gift',
      'charity',
      'salary',
      'cash',
      'card',
      'bank',
      'savings',
      'work',
      'freelance',
      'star',
    ];
    test('all 47 are still offered', () {
      final keys = categoryIcons.map((o) => o.key).toSet();
      for (final key in shipped) {
        expect(keys, contains(key), reason: key);
      }
    });
  });

  group('searchCategoryIcons', () {
    test('an empty or blank query returns everything', () {
      expect(searchCategoryIcons('').length, categoryIcons.length);
      expect(searchCategoryIcons('   ').length, categoryIcons.length);
    });

    test('matches a label, ignoring case', () {
      expect(searchCategoryIcons('PIZZA').map((o) => o.key), ['pizza']);
    });

    test('matches part of a word', () {
      expect(
        searchCategoryIcons('elec').map((o) => o.key),
        containsAll(['electricity', 'electriccar']),
      );
    });

    test('matches the key as well as the label', () {
      // "Auto rickshaw" has key "rickshaw"; "Ice cream" has key "icecream".
      expect(searchCategoryIcons('icecream').map((o) => o.key), ['icecream']);
    });

    test('every word must match', () {
      final both = searchCategoryIcons('car wash').map((o) => o.key);
      expect(both, ['carwash']);
      expect(searchCategoryIcons('car pizza'), isEmpty);
    });

    test('matches a whole section by name', () {
      final results = searchCategoryIcons('food & drink');
      expect(results, isNotEmpty);
      expect(results.every((o) => o.group == 'Food & drink'), isTrue);
    });

    test('no match gives an empty list', () {
      expect(searchCategoryIcons('qqqqzzzz'), isEmpty);
    });

    test('Bangladesh-friendly picks are available', () {
      for (final q in ['rickshaw', 'mosque', 'rice', 'cricket']) {
        expect(searchCategoryIcons(q), isNotEmpty, reason: q);
      }
    });
  });
}
