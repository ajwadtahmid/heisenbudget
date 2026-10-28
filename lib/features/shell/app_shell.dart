import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/favorite_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/quick_add_providers.dart';
import '../favorites/quick_log.dart';
import '../budgets/budgets_screen.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../trends/insights_screen.dart';
import '../settings/settings_screen.dart';
import '../transaction_form/transaction_draft.dart';
import '../transaction_form/transaction_form_screen.dart';

/// Bottom navigation scaffold. IndexedStack keeps each tab's state alive.
///
/// It is also where a launcher shortcut ("Add expense") is acted on: the shell
/// only exists once the welcome tour is done, so a shortcut chosen earlier
/// waits and is opened as soon as the shell appears.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// In the order of the bottom bar and of the tab constants in
  /// `navigation_providers.dart`.
  static const _tabs = <Widget>[
    HomeScreen(),
    BudgetsScreen(),
    InsightsScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  final _opened = <int>{homeTab};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
  }

  /// Opens the Add sheet for a pending shortcut, once.
  Future<void> _openRequested() async {
    if (!mounted) return;
    final request = ref.read(quickAddRequestProvider);
    if (request == null) return;
    ref.read(quickAddRequestProvider.notifier).clear();
    // Someone is already typing in an Add sheet: leave it alone.
    if (ref.read(addSheetCountProvider) > 0) return;

    final favoriteId = request.favoriteId;
    if (favoriteId != null) {
      final favorite = await ref
          .read(favoriteRepositoryProvider)
          .getById(favoriteId);
      if (!mounted) return;
      if (favorite != null) {
        await openFavoriteInForm(context, ref, favorite);
      } else {
        // The favorite was deleted since the shortcut was made.
        await showTransactionForm(context);
      }
      return;
    }
    await showTransactionForm(
      context,
      draft: TransactionDraft(type: request.type!),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(quickAddRequestProvider, (_, request) {
      if (request != null) _openRequested();
    });
    final index = ref.watch(shellTabProvider);
    // A tab is built when it is first opened, then kept (so each keeps its own
    // state). Insights reads months of figures: it should not do that at start.
    _opened.add(index);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _opened.contains(i) ? _tabs[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A hairline instead of a shadow separates the bar from the page.
          const Divider(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: ref.read(shellTabProvider.notifier).select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),

                selectedIcon: Icon(Icons.account_balance_wallet),

                label: 'Budgets',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
