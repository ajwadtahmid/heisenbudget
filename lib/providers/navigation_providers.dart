import 'package:flutter_riverpod/flutter_riverpod.dart';

const homeTab = 0;
const budgetsTab = 1;
const insightsTab = 2;
const historyTab = 3;
const settingsTab = 4;

/// Which bottom-navigation tab is showing. Lets "See all" on Home jump to
/// History.
final shellTabProvider = NotifierProvider<ShellTabNotifier, int>(
  ShellTabNotifier.new,
);

class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => homeTab;

  void select(int index) => state = index;
}
