import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/error_handling.dart';

void main() {
  test('financial payloads are omitted from both error handlers', () {
    final lines = <String>[];
    final original = debugPrint;
    final platform = PlatformDispatcher.instance.onError;
    final framework = FlutterError.onError;
    addTearDown(() {
      debugPrint = original;
      PlatformDispatcher.instance.onError = platform;
      FlutterError.onError = framework;
    });
    debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
    };
    installErrorHandlers();
    final error = StateError('PRIVATE_NOTE amount=1234 SQL variables');
    PlatformDispatcher.instance.onError!(
      error,
      StackTrace.fromString('PRIVATE_NOTE'),
    );
    FlutterError.onError!(FlutterErrorDetails(exception: error));
    expect(lines.join(), isNot(contains('PRIVATE_NOTE')));
    expect(lines.join(), isNot(contains('1234')));
    expect(lines.join(), contains('StateError'));
  });
  test('a stray uncaught error is noted and the app carries on', () {
    final before = PlatformDispatcher.instance.onError;
    final beforeFlutter = FlutterError.onError;
    addTearDown(() {
      PlatformDispatcher.instance.onError = before;
      FlutterError.onError = beforeFlutter;
    });
    installErrorHandlers();
    final handled = PlatformDispatcher.instance.onError!(
      StateError('nobody caught this'),
      StackTrace.current,
    );
    expect(handled, isTrue, reason: 'handled, so the app is not ended');
    expect(FlutterError.onError, isNotNull);
  });

  testWidgets('the stand-in for a broken part reads plainly, even with no '
      'theme above it', (tester) async {
    await tester.pumpWidget(const BrokenPart());
    expect(find.textContaining('Something went wrong here'), findsOneWidget);
  });
}
