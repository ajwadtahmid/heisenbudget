import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:heisenbudget/providers/period_providers.dart';

void main() {
  testWidgets(
    'today rolls over while the app stays open and timers stop on dispose',
    (tester) async {
      var now = DateTime(2026, 12, 31, 23, 59, 59);
      final container = ProviderContainer(
        overrides: [nowProvider.overrideWithValue(() => now)],
      );
      expect(container.read(clockProvider), DateTime(2026, 12, 31));
      now = DateTime(2027, 1, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(clockProvider), DateTime(2027, 1, 1));
      now = DateTime(2027, 1, 2, 12);
      await tester.pump(const Duration(minutes: 1));
      expect(container.read(clockProvider), DateTime(2027, 1, 2));
      container.dispose();
      await tester.pump(const Duration(minutes: 2));
    },
  );
}
