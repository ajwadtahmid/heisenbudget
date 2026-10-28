import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'core/constants.dart';
import 'core/theme.dart';
import 'features/shared/recurring_catch_up.dart';
import 'features/shell/app_shell.dart';
import 'features/welcome/welcome_flow.dart';
import 'domain/quick_add.dart';
import 'data/shortcuts/shortcut_service.dart';
import 'providers/backup_providers.dart';
import 'providers/budget_providers.dart';
import 'providers/comparison_providers.dart';
import 'providers/favorite_providers.dart';
import 'providers/history_providers.dart';
import 'providers/home_notice_providers.dart';
import 'providers/lab_report_providers.dart';
import 'providers/period_providers.dart';
import 'providers/quick_add_providers.dart';
import 'providers/recurring_providers.dart';
import 'providers/settings_providers.dart';
import 'providers/trends_providers.dart';
import 'providers/transaction_providers.dart';

/// What Home and History show. They are listened to here, above the
/// navigator, so they stay current while a page (a Settings page, say) covers
/// those screens. Riverpod pauses the providers of a covered screen, and
/// waking them as the page closes, in the middle of building, fails when a
/// setting changed meanwhile (currency, week start). With nothing stale, there
/// is nothing to wake.
final _keptFresh = <ProviderListenable<Object?>>[
  periodSummaryProvider,
  spendByCategoryProvider,
  recentTransactionsProvider,
  balanceProvider,
  comparisonViewProvider,
  comingUpProvider,
  historyListProvider,
  budgetOverviewProvider,
  budgetOverrunHintsProvider,
  backupReminderProvider,
  homeNoticeProvider,
  reportNoticeProvider,
  trendTotalsProvider(6),
  copyProvider,
];

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
    // The app is in English only: dates and numbers read the same on every
    // phone, whatever language it is set to.
    Intl.defaultLocale = appLocale.toString();
    WidgetsBinding.instance.addObserver(this);
    // Repeating transactions that came due while the app was closed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runRecurringCatchUp(ref);
      if (mounted) _startShortcuts();
      // Backup and CSV files made last time are readable copies of the data.
      ref.read(fileExchangeProvider).clearOldExports();
    });
  }

  /// Listens for launcher shortcuts and registers them. A chosen shortcut
  /// becomes a pending request that the shell acts on once the app is ready.
  Future<void> _startShortcuts() async {
    final service = ref.read(shortcutServiceProvider);
    await service.start((type) {
      final request = requestFromShortcut(type);
      if (mounted && request != null) {
        ref.read(quickAddRequestProvider.notifier).request(request);
      }
    });
    if (mounted) _syncShortcuts();
  }

  /// Add expense, Add income and the first favorite, if any.
  void _syncShortcuts() {
    final favorites = ref.read(favoritesProvider).value ?? const [];
    // Its name shows on the launcher, so it can be switched off.
    final on = ref.read(settingsProvider).favoriteShortcut;
    final top = favorites.isEmpty || !on ? null : favorites.first;
    ref
        .read(shortcutServiceProvider)
        .setShortcuts(
          buildShortcuts(topFavoriteId: top?.id, topFavoriteLabel: top?.label),
        );
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
      ref.read(fileExchangeProvider).clearOldExports();
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final provider in _keptFresh) {
      ref.listen(provider, (_, _) {});
    }
    // The favorite shortcut follows the first favorite.
    ref.listen(favoritesProvider, (_, _) => _syncShortcuts());
    ref.listen(
      settingsProvider.select((s) => s.favoriteShortcut),
      (_, _) => _syncShortcuts(),
    );
    // A new day may bring repeating transactions due.
    ref.listen(clockProvider, (_, _) => runRecurringCatchUp(ref));
    // Only the look-and-feel settings rebuild the whole app.
    final look = ref.watch(
      settingsProvider.select((s) => (s.accent, s.textFont, s.themeMode)),
    );
    return MaterialApp(
      scaffoldMessengerKey: ref.watch(rootMessengerKeyProvider),
      title: appName,
      theme: lightTheme(accent: look.$1, font: look.$2),
      darkTheme: darkTheme(accent: look.$1, font: look.$2),
      themeMode: look.$3,
      locale: appLocale,
      supportedLocales: const [appLocale],
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
