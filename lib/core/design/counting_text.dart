import 'package:flutter/material.dart';

/// A readout that counts to its new value instead of jumping, like an
/// instrument settling. Honors the system reduce-motion setting.
///
/// Screen readers always hear the final value, never an in-between number.
class CountingText extends StatelessWidget {
  const CountingText({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.textKey,
  });

  final int value;
  final String Function(int value) format;
  final TextStyle style;

  /// Key for the inner [Text], so tests and callers can read what is shown.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: value),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => Text(
        format(shown),
        key: textKey,
        style: style,
        maxLines: 1,
        semanticsLabel: format(value),
      ),
    );
  }
}
