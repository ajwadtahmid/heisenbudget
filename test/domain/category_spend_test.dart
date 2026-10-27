import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/category_spend.dart';

CategorySpend spend(String name, int cents, {String icon = 'category'}) =>
    CategorySpend(
      categoryId: name.hashCode,
      name: name,
      icon: icon,
      cents: cents,
    );

void main() {
  group('which categories a bar covers', () {
    CategorySpend withId(int id, String name, int cents) => CategorySpend(
      categoryId: id,
      name: name,
      icon: 'category',
      cents: cents,
    );

    test('a bar for one category names it', () {
      final bars = buildSpectrum([
        withId(7, 'Rent', 3000),
        withId(9, 'Food', 1000),
      ]);
      expect(bars[0].categoryIds, {7});
      expect(bars[1].categoryIds, {9});
    });

    test('the Rest bar names every category folded into it', () {
      final bars = buildSpectrum([
        withId(1, 'A', 700),
        withId(2, 'B', 600),
        withId(3, 'C', 500),
        withId(4, 'D', 400),
        withId(5, 'E', 300),
        withId(6, 'F', 200),
        withId(7, 'G', 100),
      ]);
      expect(bars, hasLength(6));
      expect(bars.last.isRest, isTrue);
      expect(bars.last.categoryIds, {6, 7});
      for (final bar in bars.take(5)) {
        expect(bar.categoryIds, hasLength(1));
      }
    });

    test('a bar made by hand covers nothing, so it offers no link', () {
      const bar = SpectrumBar(
        label: 'x',
        iconKey: 'category',
        cents: 1,
        permille: 1000,
      );
      expect(bar.categoryIds, isEmpty);
    });
  });

  group('buildSpectrum', () {
    test('nothing spent gives no bars', () {
      expect(buildSpectrum(const []), isEmpty);
      expect(buildSpectrum([spend('Food', 0)]), isEmpty);
    });

    test('one category is 100%', () {
      final bars = buildSpectrum([spend('Food', 2500, icon: 'restaurant')]);
      expect(bars, hasLength(1));
      expect(bars.single.label, 'Food');
      expect(bars.single.iconKey, 'restaurant');
      expect(bars.single.permille, 1000);
      expect(bars.single.percentText, '100%');
      expect(bars.single.percentDetailText, '100.0%');
      expect(bars.single.isRest, isFalse);
    });

    test('keeps the order it is given (biggest first)', () {
      final bars = buildSpectrum([
        spend('Rent', 5000),
        spend('Food', 3000),
        spend('Travel', 2000),
      ]);
      expect(bars.map((b) => b.label), ['Rent', 'Food', 'Travel']);
      expect(bars.map((b) => b.permille), [500, 300, 200]);
    });

    test('exactly five categories need no Rest bar', () {
      final bars = buildSpectrum([
        for (var i = 0; i < 5; i++) spend('C$i', 100 * (5 - i)),
      ]);
      expect(bars, hasLength(5));
      expect(bars.any((b) => b.isRest), isFalse);
    });

    test('more than five fold the rest into one bar', () {
      final bars = buildSpectrum([
        spend('A', 600),
        spend('B', 500),
        spend('C', 400),
        spend('D', 300),
        spend('E', 200),
        spend('F', 100),
        spend('G', 50),
      ]);
      expect(bars, hasLength(6));
      final rest = bars.last;
      expect(rest.isRest, isTrue);
      expect(rest.label, 'Rest');
      expect(rest.cents, 150);
      expect(rest.iconKey, 'more');
      // 150 of 2150 is 6.98%, shown to the nearest tenth: 7.0%.
      expect(rest.permille, 70);
    });

    test('a custom top count and Rest label', () {
      final bars = buildSpectrum(
        [spend('A', 300), spend('B', 200), spend('C', 100)],
        top: 2,
        restLabel: 'Other stuff',
      );
      expect(bars.map((b) => b.label), ['A', 'B', 'Other stuff']);
    });

    test('shares add up to about 100% (rounding is to a tenth)', () {
      final bars = buildSpectrum([
        spend('A', 3333),
        spend('B', 3333),
        spend('C', 3334),
      ]);
      final total = bars.fold<int>(0, (sum, b) => sum + b.permille);
      expect(total, inInclusiveRange(998, 1002));
    });

    test('percent text rounds sensibly', () {
      final bars = buildSpectrum([spend('A', 624), spend('B', 376)]);
      expect(bars.first.percentDetailText, '62.4%');
      expect(bars.first.percentText, '62%');
      expect(bars.last.percentDetailText, '37.6%');
      expect(bars.last.percentText, '38%');
    });

    test('tiny shares still show as a bar with a percentage', () {
      final bars = buildSpectrum([spend('Big', 99999), spend('Tiny', 1)]);
      expect(bars.last.cents, 1);
      expect(bars.last.percentDetailText, '0.0%');
    });

    test('huge amounts do not overflow the integer maths', () {
      final bars = buildSpectrum([
        spend('A', 99999999999),
        spend('B', 99999999999),
      ]);
      expect(bars.map((b) => b.permille), [500, 500]);
    });
  });

  group('purityPermille', () {
    test('nothing received means nothing to measure', () {
      expect(purityPermille(0, 0), isNull);
      expect(purityPermille(0, 500), isNull);
      expect(purityPermille(-5, 0), isNull);
    });

    test('nothing spent is 100%', () {
      expect(purityPermille(5000, 0), 1000);
      expect(purityText(1000), '100.0%');
    });

    test('keeping three quarters is 75%', () {
      expect(purityPermille(1000, 250), 750);
      expect(purityText(750), '75.0%');
    });

    test('spending everything or more reads 0%, never negative', () {
      expect(purityPermille(1000, 1000), 0);
      expect(purityPermille(1000, 4000), 0);
      expect(purityText(0), '0.0%');
    });

    test('rounds to the nearest tenth of a percent', () {
      // Kept 4750 of 5000 = 95.0%; kept 1 of 3 = 33.3%.
      expect(purityPermille(5000, 250), 950);
      expect(purityPermille(3, 2), 333);
      expect(purityText(333), '33.3%');
      expect(purityText(5), '0.5%');
    });

    test('works at the largest amounts', () {
      expect(purityPermille(99999999999, 49999999999), 500);
    });
  });
}
