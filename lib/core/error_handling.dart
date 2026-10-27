import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps one broken screen or a stray error from taking the whole app down,
/// and swaps Flutter's grey error box for a plain message. Errors are only
/// written to the debug console: the app has no network and sends nothing.
void installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  // Errors nothing caught (a failed future with no listener): note them and
  // carry on, rather than ending the app.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  // Debug builds keep Flutter's own red error screen, which names the cause.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const BrokenPart();
  }
}

/// What stands in for a part of a screen that failed to build.
class BrokenPart extends StatelessWidget {
  const BrokenPart({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Something went wrong here.\nGo back and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF8A9490)),
          ),
        ),
      ),
    );
  }
}
