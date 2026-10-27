import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/error_handling.dart';

void main() {
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
