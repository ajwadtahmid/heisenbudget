import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/search.dart';

bool hit(
  String query, {
  String category = 'Food',
  String? note,
  int cents = 450,
}) =>
    SearchQuery.parse(query)
        .matches(category: category, note: note, amountCents: cents);

void main() {
  group('words', () {
    test('an empty or blank query matches everything', () {
      for (final q in ['', '   ', '\t\n']) {
        final parsed = SearchQuery.parse(q);
        expect(parsed.isEmpty, isTrue, reason: '"$q"');
        expect(hit(q), isTrue);
      }
    });

    test('matches the note, ignoring case', () {
      expect(hit('coffee', note: 'Iced COFFEE with oat milk'), isTrue);
      expect(hit('COFFEE', note: 'coffee'), isTrue);
      expect(hit('tea', note: 'coffee'), isFalse);
    });

    test('matches the category name', () {
      expect(hit('foo', category: 'Food'), isTrue);
      expect(hit('rent', category: 'Food'), isFalse);
    });

    test('matches anywhere inside a word', () {
      expect(hit('ffe', note: 'coffee'), isTrue);
    });

    test('every word has to match, in any order and any field', () {
      expect(hit('coffee food', note: 'coffee', category: 'Food'), isTrue);
      expect(hit('food coffee', note: 'coffee', category: 'Food'), isTrue);
      expect(hit('coffee rent', note: 'coffee', category: 'Food'), isFalse);
    });

    test('extra spaces and repeated words do not matter', () {
      final q = SearchQuery.parse('  coffee   COFFEE  tea ');
      expect(q.terms, ['coffee', 'tea']);
    });

    test('a missing note simply does not match', () {
      expect(hit('coffee', note: null, category: 'Food'), isFalse);
    });

    test('works for Bangla and accented text', () {
      expect(hit('চা', note: 'সকালের চা'), isTrue);
      expect(hit('café', note: 'Un CAFÉ noir'), isTrue);
      expect(hit('ÉCOLE', note: 'école'), isTrue);
    });

    test('regex and SQL wildcard characters are plain text', () {
      expect(hit('%', note: '50% off'), isTrue);
      expect(hit('%', note: 'no percent'), isFalse);
      expect(hit('_', note: 'a_b'), isTrue);
      expect(hit('_', note: 'ab'), isFalse);
      expect(hit('.*', note: 'anything'), isFalse);
      expect(hit('(', note: 'f(x)'), isTrue);
      expect(hit(r'\', note: r'a\b'), isTrue);
    });

    test('a very long query is cut to the limit', () {
      final q = SearchQuery.parse('a' * 500);
      expect(q.terms.single.length, maxSearchLength);
    });
  });

  group('amounts', () {
    test('a whole number matches that amount to the cent range', () {
      expect(hit('4', cents: 400), isTrue);
      expect(hit('4', cents: 450), isTrue);
      expect(hit('4', cents: 499), isTrue);
      expect(hit('4', cents: 500), isFalse);
      expect(hit('4', cents: 399), isFalse);
      expect(hit('4', cents: 4000), isFalse, reason: '40.00 is not 4');
    });

    test('one decimal digit matches a tenth', () {
      expect(hit('4.5', cents: 450), isTrue);
      expect(hit('4.5', cents: 459), isTrue);
      expect(hit('4.5', cents: 460), isFalse);
      expect(hit('4.5', cents: 440), isFalse);
    });

    test('two decimal digits match exactly', () {
      expect(hit('4.50', cents: 450), isTrue);
      expect(hit('4.50', cents: 451), isFalse);
      expect(hit('4.05', cents: 405), isTrue);
    });

    test('a decimal comma works like a dot', () {
      expect(hit('4,50', cents: 450), isTrue);
      expect(hit('4,5', cents: 455), isTrue);
    });

    test('a trailing dot is the whole number', () {
      expect(hit('4.', cents: 425), isTrue);
    });

    test('a grouped thousand is read as one number', () {
      expect(hit('1,200', cents: 120000), isTrue);
      expect(hit('1,200', cents: 120099), isTrue);
      expect(hit('1,200.50', cents: 120050), isTrue);
      expect(hit('1,200.50', cents: 120051), isFalse);
    });

    test('a number also matches note text', () {
      expect(hit('4', note: 'Room 4', cents: 90000), isTrue);
      expect(hit('4', note: 'Room 5', cents: 90000), isFalse);
    });

    test('text words are not amounts', () {
      expect(hit('abc', cents: 450), isFalse);
      expect(hit('4a', cents: 450), isFalse);
    });

    test('words and a number combine', () {
      expect(hit('coffee 4', note: 'coffee', cents: 450), isTrue);
      expect(hit('coffee 4', note: 'coffee', cents: 550), isFalse);
      expect(hit('coffee 4', note: 'tea', cents: 450), isFalse);
    });

    test('huge numbers do not crash', () {
      expect(hit('99999999999999999999', cents: 450), isFalse);
      expect(hit('1234567890', cents: 450), isFalse);
    });
  });

  group('highlights', () {
    test('marks every occurrence, ignoring case', () {
      final q = SearchQuery.parse('co');
      expect(q.highlights('Coffee Corner'), [(0, 2), (7, 9)]);
    });

    test('overlapping and touching matches merge into one', () {
      final q = SearchQuery.parse('cof off');
      expect(q.highlights('coffee'), [(0, 4)]);
      final q2 = SearchQuery.parse('ab cd');
      expect(q2.highlights('abcd'), [(0, 4)]);
    });

    test('nothing to mark when nothing matches or the query is empty', () {
      expect(SearchQuery.parse('zzz').highlights('coffee'), isEmpty);
      expect(SearchQuery.parse('').highlights('coffee'), isEmpty);
      expect(SearchQuery.parse('a').highlights(''), isEmpty);
    });

    test('a number is marked where it appears in text', () {
      expect(SearchQuery.parse('4').highlights('Room 4B'), [(5, 6)]);
    });

    test('offsets always point at the matched text', () {
      for (final text in ['İx İ x', 'ẞtraße', 'ΑΣΣ', 'চা চা']) {
        final q = SearchQuery.parse('x ss σ চা');
        for (final (a, b) in q.highlights(text)) {
          expect(a >= 0 && b <= text.length && a < b, isTrue, reason: text);
        }
      }
    });
  });
}
