import 'package:flutter/widgets.dart';

/// Caps how far large system text sizes may enlarge [child], at 130% by
/// default. For big numeric readouts only: a 32sp amount at 200% would be 64sp
/// and could not fit beside its currency symbol. Everything around it still
/// scales fully, and the number stays easy to read.
class ClampedTextScale extends StatelessWidget {
  const ClampedTextScale({super.key, this.max = 1.3, required this.child});

  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: max)),
      child: child,
    );
  }
}
