import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/formatters.dart';
import 'package:heisenbudget/core/money_parser.dart';
import 'package:heisenbudget/domain/date_range.dart';

void main() {
  group('parseMoney accepts', () {
    const cases = {
      '12': 1200,
      '12.5': 1250,
      '12.50': 1250,
      '12,50': 1250,
      '12,5': 1250,
      ' 12 ': 1200,
      '0.01': 1,
      '.5': 50,
      '999999999.99': 99999999999,
      '1 2 . 5 0': 1250,
    };
    cases.forEach((input, cents) {
      test('"$input" -> $cents', () {
        final r = parseMoney(input);
        expect(r.isValid, isTrue, reason: r.error);
        expect(r.cents, cents);
      });
    });
  });

  group('parseMoney rejects', () {
    const cases = {
      '': errorEmptyAmount,
      '   ': errorEmptyAmount,
      '0': errorNotPositive,
      '0.00': errorNotPositive,
      '-5': errorNotPositive,
      'abc': errorInvalidAmount,
      '12a': errorInvalidAmount,
      '.': errorInvalidAmount,
      '1.2.3': errorInvalidAmount,
      '1.234': errorTooManyDecimals,
      '12.505': errorTooManyDecimals,
      '1000000000': errorTooLarge,
      '999999999.99999': errorTooManyDecimals,
      '99999999999999999999': errorTooLarge,
      '1,234.56': errorThousandsSeparator,
      '1,234': errorThousandsSeparator,
      '1,234,567': errorThousandsSeparator,
    };
    cases.forEach((input, error) {
      test('"$input" -> "$error"', () {
        final r = parseMoney(input);
        expect(r.isValid, isFalse);
        expect(r.error, error);
      });
    });

    test('anything above 999,999,999.99', () {
      expect(parseMoney('1000000000.00').error, errorTooLarge);
      expect(parseMoney('999999999.99').isValid, isTrue);
    });
  });

  group('parseMoney for the starting balance', () {
    test('allows negatives and zero when asked', () {
      expect(
        parseMoney('-5', allowNegative: true, allowZero: true).cents,
        -500,
      );
      expect(parseMoney('-12,50', allowNegative: true).cents, -1250);
      expect(parseMoney('0', allowNegative: true, allowZero: true).cents, 0);
    });

    test('still rejects a lone minus, garbage and thousands separators', () {
      expect(parseMoney('-', allowNegative: true).isValid, isFalse);
      expect(parseMoney('-abc', allowNegative: true).isValid, isFalse);
      expect(
        parseMoney('-1,234.56', allowNegative: true).error,
        errorThousandsSeparator,
      );
    });

    test('zero is rejected unless allowZero', () {
      expect(parseMoney('0', allowNegative: true).error, errorNotPositive);
    });

    test('the maximum applies to negative amounts too', () {
      expect(
        parseMoney('-1000000000', allowNegative: true).error,
        errorTooLarge,
      );
    });
  });

  group('money arithmetic', () {
    test('summing 10 x 0.10 yields exactly 100 cents', () {
      final total = List.generate(
        10,
        (_) => parseMoney('0.10').cents!,
      ).reduce((a, b) => a + b);
      expect(total, 100);
    });
  });

  group('formatMoney', () {
    test('formats cents with symbol, grouping and two decimals', () {
      expect(formatMoney(0, r'$'), r'$0.00');
      expect(formatMoney(5, r'$'), r'$0.05');
      expect(formatMoney(99, r'$'), r'$0.99');
      expect(formatMoney(100, r'$'), r'$1.00');
      expect(formatMoney(123456789, r'$'), r'$1,234,567.89');
      expect(formatMoney(99999999999, r'$'), r'$999,999,999.99');
    });

    test('negative amounts show a minus sign before the symbol', () {
      expect(formatMoney(-1250, r'$'), r'-$12.50');
      expect(formatMoney(-5, r'$'), r'-$0.05');
      expect(formatMoney(-123456789, '€'), '-€1,234,567.89');
    });

    test('showPlus adds + to positive amounts only', () {
      expect(formatMoney(1250, r'$', showPlus: true), r'+$12.50');
      expect(formatMoney(0, r'$', showPlus: true), r'$0.00');
      expect(formatMoney(-1250, r'$', showPlus: true), r'-$12.50');
    });

    test('a letter symbol gets a space', () {
      expect(formatMoney(1250, 'Rs'), 'Rs 12.50');
      expect(formatMoney(-1250, 'CHF'), '-CHF 12.50');
    });

    test('input text round trips with the parser', () {
      expect(centsToInputText(1250), '12.50');
      expect(centsToInputText(5), '0.05');
      expect(centsToInputText(-1250), '-12.50');
      expect(parseMoney(centsToInputText(123456)).cents, 123456);
    });
  });

  group('date formatting', () {
    DateTime d(int y, int m, int day) => DateTime(y, m, day);

    test('range in one year', () {
      expect(
        formatRange(DateRange(d(2026, 10, 1), d(2026, 10, 7))),
        'Oct 1 – Oct 7, 2026',
      );
    });

    test('range across a year boundary shows both years', () {
      expect(
        formatRange(DateRange(d(2026, 12, 28), d(2027, 1, 3))),
        'Dec 28, 2026 – Jan 3, 2027',
      );
    });

    test('single day range', () {
      expect(
        formatRange(DateRange(d(2026, 10, 5), d(2026, 10, 5))),
        'Oct 5, 2026',
      );
    });

    test('day header and month', () {
      expect(formatDayHeader(d(2026, 10, 5)), 'Mon, Oct 5, 2026');
      expect(formatMonth(d(2026, 10, 5)), 'October 2026');
    });
  });
}
