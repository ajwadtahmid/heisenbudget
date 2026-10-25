import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/currencies.dart';
import 'package:heisenbudget/core/formatters.dart';

void main() {
  test('Bangladesh is included, with the taka sign', () {
    final bdt = currencyByCode('BDT')!;
    expect(bdt.name, 'Bangladeshi Taka');
    expect(bdt.symbol, '৳');
    expect(bdt.label, '৳ Bangladeshi Taka (BDT)');
  });

  test('codes are unique, 3 letters, and every entry is complete', () {
    final codes = currencies.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final c in currencies) {
      expect(c.code, matches(RegExp(r'^[A-Z]{3}$')));
      expect(c.name.trim(), isNotEmpty);
      expect(c.symbol.trim(), isNotEmpty);
    }
  });

  test('the dropdown order is alphabetical by name and has every currency', () {
    final names = currenciesByName.map((c) => c.name).toList();
    expect(names, [...names]..sort());
    expect(currenciesByName.length, currencies.length);
    expect(names.first, 'Argentine Peso');
  });

  test('the default currency exists', () {
    expect(currencyByCode(defaultCurrencyCode), isNotNull);
  });

  test('lookup is exact and tolerant of null / unknown codes', () {
    expect(currencyByCode('EUR')!.symbol, '€');
    expect(currencyByCode('eur'), isNull);
    expect(currencyByCode('ZZZ'), isNull);
    expect(currencyByCode(null), isNull);
  });

  test('amounts format with the chosen symbol', () {
    expect(formatMoney(123456, currencyByCode('BDT')!.symbol), '৳1,234.56');
    expect(formatMoney(-500, currencyByCode('INR')!.symbol), '-₹5.00');
    expect(formatMoney(1250, currencyByCode('CHF')!.symbol), 'CHF 12.50');
  });
}
