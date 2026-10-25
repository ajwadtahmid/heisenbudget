import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<void> chooseTheme(WidgetTester tester, String label) async {
  await goToTab(tester, 'Settings');
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('theme-mode')),
      matching: find.text(label),
    ),
  );
  await settle(tester);
}

MaterialApp appWidget(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

Brightness shownBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

void main() {
  group('SettingsRepository theme mode', () {
    Future<SettingsRepository> makeRepo([
      Map<String, Object> initial = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initial);
      return SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
    }

    test('defaults to following the system', () async {
      expect((await makeRepo()).load().themeMode, ThemeMode.system);
    });

    test('saves and reads every mode', () async {
      final repo = await makeRepo();
      for (final mode in ThemeMode.values) {
        await repo.setThemeMode(mode);
        expect(repo.load().themeMode, mode);
      }
    });

    test('an unrecognised saved value falls back to the system', () async {
      final repo = await makeRepo({'theme_mode': 'purple'});
      expect(repo.load().themeMode, ThemeMode.system);
    });
  });

  testWidgets('Appearance offers System, Light and Dark; System is selected', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'Settings');

    for (final label in ['System', 'Light', 'Dark']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('theme-mode')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    final selector = tester.widget<SegmentedButton<ThemeMode>>(
      find.descendant(
        of: find.byKey(const ValueKey('theme-mode')),
        matching: find.byType(SegmentedButton<ThemeMode>),
      ),
    );
    expect(selector.selected, {ThemeMode.system});
    expect(appWidget(tester).themeMode, ThemeMode.system);
    await disposeEnv(tester, env);
  });

  testWidgets('System follows the phone: light phone -> light app', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(shownBrightness(tester), Brightness.light);
    await disposeEnv(tester, env);
  });

  testWidgets('System follows the phone: dark phone -> dark app', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(shownBrightness(tester), Brightness.dark);
    await disposeEnv(tester, env);
  });

  testWidgets('choosing Dark turns dark mode on even on a light phone', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(shownBrightness(tester), Brightness.light);

    await chooseTheme(tester, 'Dark');

    expect(appWidget(tester).themeMode, ThemeMode.dark);
    expect(shownBrightness(tester), Brightness.dark);
    expect(env.prefs.getString('theme_mode'), 'dark');
    // The extra colors switch with it.
    final colors = Theme.of(tester.element(find.byType(Scaffold).first))
        .extension<AppColors>()!;
    expect(colors.received, AppColors.dark.received);
    await disposeEnv(tester, env);
  });

  testWidgets('choosing Light overrides a dark phone', (tester) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(shownBrightness(tester), Brightness.dark);

    await chooseTheme(tester, 'Light');

    expect(shownBrightness(tester), Brightness.light);
    expect(env.prefs.getString('theme_mode'), 'light');
    await disposeEnv(tester, env);
  });

  testWidgets('switching back to System follows the phone again', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await chooseTheme(tester, 'Dark');
    expect(shownBrightness(tester), Brightness.dark);

    await chooseTheme(tester, 'System');
    expect(shownBrightness(tester), Brightness.light);
    await disposeEnv(tester, env);
  });

  testWidgets('a saved Dark choice is applied at start-up', (tester) async {
    final env = await createEnv(tester, prefs: {'theme_mode': 'dark'});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    expect(shownBrightness(tester), Brightness.dark);
    await goToTab(tester, 'Settings');
    final selector = tester.widget<SegmentedButton<ThemeMode>>(
      find.descendant(
        of: find.byKey(const ValueKey('theme-mode')),
        matching: find.byType(SegmentedButton<ThemeMode>),
      ),
    );
    expect(selector.selected, {ThemeMode.dark});
    await disposeEnv(tester, env);
  });

  testWidgets('every screen renders in dark mode without errors', (
    tester,
  ) async {
    final env = await createEnv(tester, prefs: {'theme_mode': 'dark'});
    await addIncome(tester, env, 500000, DateTime(2026, 10, 1));
    await addExpense(
      tester,
      env,
      12345,
      DateTime(2026, 10, 2),
      note: 'dinner out',
    );
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    for (final tab in ['Home', 'History', 'Settings']) {
      await goToTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }

    // Sheets and dialogs too.
    await goToTab(tester, 'History');
    await tester.tap(find.byTooltip('Filter'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'filter sheet');
    await tester.tap(find.text('Done'));
    await settle(tester);

    await goToTab(tester, 'Home');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'add sheet');
    await disposeEnv(tester, env);
  });

  test('dark and light themes keep readable contrast for text on surfaces', () {
    double luminance(Color c) => c.computeLuminance();
    for (final theme in [lightTheme(), darkTheme()]) {
      final scheme = theme.colorScheme;
      final contrast = (luminance(scheme.surface) - luminance(scheme.onSurface))
          .abs();
      expect(contrast, greaterThan(0.5), reason: '${theme.brightness}');
    }
    // Money colors stand out from the dark surface.
    final dark = darkTheme().colorScheme;
    for (final color in [AppColors.dark.received, AppColors.dark.spent]) {
      expect(
        (luminance(color) - luminance(dark.surface)).abs(),
        greaterThan(0.3),
      );
    }
  });
}
