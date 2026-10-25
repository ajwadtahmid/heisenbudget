import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/copy.dart';
import 'package:heisenbudget/core/design/counting_text.dart';
import 'package:heisenbudget/core/design/leader_row.dart';
import 'package:heisenbudget/core/design/section_label.dart';
import 'package:heisenbudget/core/design/tick_ruler.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/domain/date_range.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget host(Widget child, {double width = 360, ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? darkTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('colour contrast (WCAG AA) in every mode and accent', () {
    for (final brightness in Brightness.values) {
      for (final accent in AccentColor.values) {
        test('${brightness.name} / ${accent.name}', () {
          final c = AppColors.resolve(brightness, accent);
          for (final ground in [c.ground, c.panel]) {
            expect(
              contrast(c.text, ground),
              greaterThanOrEqualTo(7),
              reason: 'text',
            );
            expect(
              contrast(c.dim, ground),
              greaterThanOrEqualTo(4.5),
              reason: 'dim',
            );
            expect(
              contrast(c.received, ground),
              greaterThanOrEqualTo(4.5),
              reason: 'received',
            );
            expect(
              contrast(c.spent, ground),
              greaterThanOrEqualTo(4.5),
              reason: 'spent',
            );
            expect(
              contrast(c.error, ground),
              greaterThanOrEqualTo(4.5),
              reason: 'error',
            );
            expect(
              contrast(c.accent, ground),
              greaterThanOrEqualTo(4.5),
              reason: 'accent',
            );
          }
          expect(
            contrast(c.onAccent, c.accent),
            greaterThanOrEqualTo(4.5),
            reason: 'label on the accent button',
          );
          expect(
            contrast(c.spentFill, c.ground),
            greaterThanOrEqualTo(3),
            reason: 'chart bars',
          );
          expect(
            contrast(c.faint, c.ground),
            greaterThanOrEqualTo(3),
            reason: 'tick marks and outlines',
          );
        });
      }
    }

    test('Received and Spent never depend on the accent', () {
      for (final brightness in Brightness.values) {
        final base = AppColors.resolve(brightness, AccentColor.assay);
        for (final accent in AccentColor.values) {
          final c = AppColors.resolve(brightness, accent);
          expect(c.received, base.received);
          expect(c.spent, base.spent);
        }
      }
    });

    test('Spent is not red, and not the same as Received', () {
      for (final brightness in Brightness.values) {
        final c = AppColors.resolve(brightness, AccentColor.assay);
        expect(c.spent, isNot(c.received));
        expect(
          HSLColor.fromColor(c.spent).hue,
          inInclusiveRange(25, 50),
          reason: 'amber hue',
        );
      }
    });
  });

  group('names saved in preferences', () {
    test('accent and font fall back to the defaults', () {
      expect(AccentColor.fromName('ice'), AccentColor.ice);
      expect(AccentColor.fromName('nope'), AccentColor.assay);
      expect(AccentColor.fromName(null), AccentColor.assay);
      expect(AppFont.fromName('inter'), AppFont.inter);
      expect(AppFont.fromName('comic'), AppFont.geist);
      expect(AppFont.fromName(null), AppFont.geist);
    });

    test('the font families match what pubspec bundles', () {
      expect(AppFont.geist.family, 'Geist');
      expect(AppFont.inter.family, 'Inter');
      expect(AppFont.atkinson.family, 'AtkinsonHyperlegible');
      expect(AppFont.system.family, isNull);
      expect(monoFamily, 'GeistMono');
    });

    test('there is no amber accent (amber is the Spent colour)', () {
      for (final accent in AccentColor.values) {
        final hue = HSLColor.fromColor(accent.dark).hue;
        final saturation = HSLColor.fromColor(accent.dark).saturation;
        expect(
          hue > 25 && hue < 50 && saturation > 0.5,
          isFalse,
          reason: accent.name,
        );
      }
    });
  });

  group('theme', () {
    test('the accent becomes the primary colour in both modes', () {
      for (final accent in AccentColor.values) {
        expect(darkTheme(accent: accent).colorScheme.primary, accent.dark);
        expect(lightTheme(accent: accent).colorScheme.primary, accent.light);
      }
    });

    test('the chosen font is applied to the text theme', () {
      expect(
        lightTheme(font: AppFont.inter).textTheme.bodyMedium!.fontFamily,
        'Inter',
      );
      expect(
        darkTheme(font: AppFont.atkinson).textTheme.titleLarge!.fontFamily,
        'AtkinsonHyperlegible',
      );
      expect(darkTheme().textTheme.bodyLarge!.fontFamily, 'Geist');
      expect(
        darkTheme(font: AppFont.system).textTheme.bodyMedium!.fontFamily,
        isNot('Geist'),
      );
    });

    test('numbers always use Geist Mono with tabular figures', () {
      final style = monoText(size: 20);
      expect(style.fontFamily, 'GeistMono');
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('depth comes from hairlines, not shadows', () {
      for (final theme in [lightTheme(), darkTheme()]) {
        expect(theme.floatingActionButtonTheme.elevation, 0);
        expect(theme.navigationBarTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
      }
    });

    test('corners are small: nothing is a pill', () {
      expect(Radii.chip, lessThanOrEqualTo(12));
      expect(Radii.panel, lessThanOrEqualTo(16));
      expect(Radii.sheet, lessThanOrEqualTo(24));
    });

    test('the colours travel with the theme', () {
      final c = darkTheme().extension<AppColors>()!;
      expect(c.ground, const Color(0xFF070A09));
      expect(
        lightTheme().extension<AppColors>()!.ground,
        const Color(0xFFF4F6F5),
      );
    });

    test('AppColors lerps and copies', () {
      final mid = AppColors.dark.lerp(AppColors.light, 0.5);
      expect(mid.ground, isNot(AppColors.dark.ground));
      expect(AppColors.dark.lerp(null, 0.5), AppColors.dark);
      expect(AppColors.dark.copyWith(spent: Colors.black).spent, Colors.black);
      expect(AppColors.dark.warning, AppColors.dark.spent);
    });
  });

  group('Copy (Lab flavor)', () {
    const lab = Copy(lab: true);
    const plain = Copy(lab: false);

    test('lab wording is instrument-style, plain wording is plain', () {
      expect(lab.emptyRecent, contains('Flat line'));
      expect(plain.emptyRecent, isNot(contains('Flat line')));
      expect(lab.chartTitle, 'Spectrum');
      expect(plain.chartTitle, 'Spending');
    });

    test('every string exists in both flavors and is non-empty', () {
      for (final copy in [lab, plain]) {
        for (final text in [
          copy.emptyRecent,
          copy.emptyHistory,
          copy.emptyChart,
          copy.chartTitle,
        ]) {
          expect(text.trim(), isNotEmpty);
        }
      }
    });

    test('purity wording: PURITY with Lab flavor, SAVED without', () {
      expect(lab.purity('95.0%'), 'PURITY 95.0%');
      expect(plain.purity('95.0%'), 'SAVED 95.0%');
    });

    test('banned phrases never appear', () {
      const banned = ['say my name', 'i am the one', 'yeah science', '99.1'];
      for (final copy in [lab, plain]) {
        final all = [
          copy.emptyRecent,
          copy.emptyHistory,
          copy.emptyChart,
          copy.chartTitle,
          copy.purity('0.0%'),
        ].join(' ').toLowerCase();
        for (final phrase in banned) {
          expect(all, isNot(contains(phrase)));
        }
      }
    });
  });

  group('LeaderRow', () {
    testWidgets('shows label and value, and speaks them together', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const LeaderRow(
            label: 'SPENT',
            value: r'-$250.00',
            icon: Icons.arrow_upward,
          ),
        ),
      );
      expect(find.text('SPENT'), findsOneWidget);
      expect(find.text(r'-$250.00'), findsOneWidget);
      expect(find.bySemanticsLabel(r'SPENT -$250.00'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('scales down instead of overflowing when space is tight', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const LeaderRow(
            label: 'RECEIVED',
            value: r'+$999,999,999.99',
            icon: Icons.arrow_downward,
          ),
          width: 180,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(r'+$999,999,999.99'), findsOneWidget);
    });

    testWidgets('fits at 200% text on a narrow screen', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        host(const LeaderRow(label: 'NET', value: r'+$4,750.00'), width: 300),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a 40dp minimum height', (tester) async {
      await tester.pumpWidget(
        host(const LeaderRow(label: 'NET', value: r'$1.00')),
      );
      expect(
        tester.getSize(find.byType(LeaderRow)).height,
        greaterThanOrEqualTo(40),
      );
    });
  });

  group('SectionLabel', () {
    testWidgets(
      'upper-cases the text, rules out to the right, shows the action',
      (tester) async {
        await tester.pumpWidget(
          host(
            SectionLabel(
              'Recent',
              trailing: TextButton(
                onPressed: () {},
                child: const Text('See all'),
              ),
            ),
          ),
        );
        expect(find.text('RECENT'), findsOneWidget);
        expect(find.byType(Divider), findsOneWidget);
        expect(find.text('See all'), findsOneWidget);
      },
    );

    testWidgets('is a heading for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const SectionLabel('Spending')));
      final data = tester.getSemantics(find.text('SPENDING'));
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('TickRuler', () {
    DateRange month() =>
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31));

    for (final (name, range, today) in [
      (
        'mid-month',
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        DateTime(2026, 10, 15),
      ),
      (
        'a past period',
        DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        DateTime(2026, 10, 15),
      ),
      (
        'a future period',
        DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
        DateTime(2026, 10, 15),
      ),
      (
        'a single day',
        DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 5)),
        DateTime(2026, 10, 5),
      ),
      (
        'a long custom range (ticks by week)',
        DateRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        DateTime(2026, 10, 15),
      ),
    ]) {
      testWidgets('draws for $name without errors', (tester) async {
        await tester.pumpWidget(host(TickRuler(range: range, today: today)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TickRuler), findsOneWidget);
      });
    }

    testWidgets('is decoration only: hidden from screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(TickRuler(range: month(), today: DateTime(2026, 10, 15))),
      );
      expect(
        find.descendant(
          of: find.byType(TickRuler),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
    });

    testWidgets('fills in over time', (tester) async {
      await tester.pumpWidget(
        host(TickRuler(range: month(), today: DateTime(2026, 10, 15))),
      );
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('is drawn instantly with reduce-motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        host(TickRuler(range: month(), today: DateTime(2026, 10, 15))),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('CountingText', () {
    String format(int v) => '\$$v';

    testWidgets('counts to a new value instead of jumping', (tester) async {
      Widget build(int value) => host(
        CountingText(
          value: value,
          format: format,
          style: const TextStyle(),
          textKey: const ValueKey('n'),
        ),
      );
      await tester.pumpWidget(build(100));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('n'))).data,
        r'$100',
      );

      await tester.pumpWidget(build(200));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.widget<Text>(find.byKey(const ValueKey('n'))).data!;
      expect(mid, isNot(r'$100'));
      expect(mid, isNot(r'$200'));

      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('n'))).data,
        r'$200',
      );
    });

    testWidgets('screen readers always hear the final value', (tester) async {
      final handle = tester.ensureSemantics();
      Widget build(int value) => host(
        CountingText(value: value, format: format, style: const TextStyle()),
      );
      await tester.pumpWidget(build(100));
      await tester.pumpWidget(build(500));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.bySemanticsLabel(r'$500'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('does not animate with reduce-motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      Widget build(int value) => host(
        CountingText(
          value: value,
          format: format,
          style: const TextStyle(),
          textKey: const ValueKey('n'),
        ),
      );
      await tester.pumpWidget(build(1));
      await tester.pumpWidget(build(9));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('n'))).data, r'$9');
    });
  });

  group('review fixes', () {
    test('the default accent is visibly different from the Received green', () {
      for (final brightness in Brightness.values) {
        final c = AppColors.resolve(brightness, AccentColor.assay);
        final accent = HSLColor.fromColor(c.accent).hue;
        final received = HSLColor.fromColor(c.received).hue;
        expect(
          (accent - received).abs(),
          greaterThanOrEqualTo(15),
          reason: brightness.name,
        );
      }
    });

    test('buttons and the add key are small-radius keys, not pills', () {
      final theme = darkTheme();
      final fab =
          theme.floatingActionButtonTheme.shape as RoundedRectangleBorder;
      expect(fab.borderRadius, BorderRadius.circular(Radii.input));
      final filled = theme.filledButtonTheme.style!.shape!.resolve(
        {},
      ) as RoundedRectangleBorder;
      expect(filled.borderRadius, BorderRadius.circular(Radii.input));
      expect(Radii.input, lessThanOrEqualTo(10));
    });
  });
}
