import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'features/shell/app_shell.dart';
import 'features/welcome/welcome_flow.dart';
import 'providers/period_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/transaction_providers.dart';

class HeisenbudgetApp extends ConsumerStatefulWidget {
  const HeisenbudgetApp({super.key});

  @override
  ConsumerState<HeisenbudgetApp> createState() => _HeisenbudgetAppState();
}

class _HeisenbudgetAppState extends ConsumerState<HeisenbudgetApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app after midnight: pick up the new "today".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(clockProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the look-and-feel settings rebuild the whole app.
    final look = ref.watch(
      settingsProvider.select((s) => (s.accent, s.textFont, s.themeMode)),
    );
    return MaterialApp(
      title: appName,
      theme: lightTheme(accent: look.$1, font: look.$2),
      darkTheme: darkTheme(accent: look.$1, font: look.$2),
      themeMode: look.$3,
      home: const _Root(),
    );
  }
}

/// First run shows the welcome tour; everyone else lands on the app at once
/// (no blank frame, because a finished setup needs no check).
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const shell = AppShell(key: ValueKey('shell'));
    final done = ref.watch(settingsProvider.select((s) => s.onboardingDone));

    final Widget child;
    if (done) {
      child = shell;
    } else {
      child = ref
          .watch(needsWelcomeProvider)
          .when(
            // A blank ground for the instant it takes to look.
            loading: () => ColoredBox(
              key: const ValueKey('blank'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const SizedBox.expand(),
            ),
            error: (_, _) => shell,
            data: (needs) =>
                needs ? const WelcomeFlow(key: ValueKey('welcome')) : shell,
          );
    }

    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      child: child,
    );
  }
}
