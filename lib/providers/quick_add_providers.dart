import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shortcuts/shortcut_service.dart';
import '../domain/quick_add.dart';

/// The launcher shortcuts. Tests override it with a fake.
final shortcutServiceProvider = Provider<ShortcutService>(
  (ref) => const ShortcutService(),
);

/// A shortcut that was chosen and has not been acted on yet. It waits here
/// until the app is ready (past the welcome tour), then the shell opens the
/// Add sheet and clears it.
final quickAddRequestProvider =
    NotifierProvider<QuickAddRequestNotifier, QuickAddRequest?>(
      QuickAddRequestNotifier.new,
    );

class QuickAddRequestNotifier extends Notifier<QuickAddRequest?> {
  @override
  QuickAddRequest? build() => null;

  void request(QuickAddRequest request) => state = request;

  void clear() => state = null;
}

/// How many Add/Edit sheets are open. A shortcut chosen while one is open is
/// ignored, so nothing someone is typing is lost.
final addSheetCountProvider = NotifierProvider<AddSheetCount, int>(
  AddSheetCount.new,
);

class AddSheetCount extends Notifier<int> {
  @override
  int build() => 0;

  // A sheet's update is deferred a moment, so the whole app can be gone by
  // then (shutdown, tests); there is nothing left to count.
  void opened() {
    if (ref.mounted) state = state + 1;
  }

  void closed() {
    if (ref.mounted) state = state > 0 ? state - 1 : 0;
  }
}
