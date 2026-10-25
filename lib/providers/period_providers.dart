import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/settings_repository.dart';
import '../domain/date_range.dart';
import '../domain/iso_date.dart';
import '../domain/period.dart';
import 'settings_providers.dart';

/// Where "now" comes from. Tests override this with a fixed time.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's date (no time of day). Call [ClockNotifier.refresh] when the app
/// comes back to the foreground so a new day is picked up after midnight.
final clockProvider = NotifierProvider<ClockNotifier, DateTime>(
  ClockNotifier.new,
);

class ClockNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(ref.read(nowProvider)());

  void refresh() {
    final today = dateOnly(ref.read(nowProvider)());
    if (today != state) state = today;
  }
}

/// Turns a [Period] into dates with the user's week settings.
/// Clamps first so a stale "Week 6" can never throw.
DateRange rangeOf(Period period, AppSettings settings) {
  final safe = clampPeriod(period, settings.weekMode, settings.weekStartDay);
  return resolvePeriod(safe, settings.weekMode, settings.weekStartDay);
}

/// The period picked on the Home screen (default: this month).
final selectedPeriodProvider = NotifierProvider<SelectedPeriodNotifier, Period>(
  SelectedPeriodNotifier.new,
);

class SelectedPeriodNotifier extends Notifier<Period> {
  @override
  Period build() {
    // Changing the week settings can make "Week 6" invalid: clamp it.
    ref.listen(
      settingsProvider.select((s) => (s.weekMode, s.weekStartDay)),
      (_, next) => state = clampPeriod(state, next.$1, next.$2),
    );
    return ThisMonth(ref.read(clockProvider));
  }

  void select(Period period) => state = period;

  /// Steps the ‹ › arrows: -1 for previous, +1 for next.
  void step(int delta) {
    final s = ref.read(settingsProvider);
    state = stepPeriod(state, delta, s.weekMode, s.weekStartDay);
  }
}

/// The selected period as concrete dates.
final periodRangeProvider = Provider<DateRange>((ref) {
  return rangeOf(
    ref.watch(selectedPeriodProvider),
    ref.watch(settingsProvider),
  );
});
