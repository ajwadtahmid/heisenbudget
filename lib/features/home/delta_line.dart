import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/comparison.dart';

/// One quiet line under Spent or Received: `▼ 12% vs Sep 1–25`.
///
/// The triangle and the words carry the meaning; the text is dim, never the
/// green or amber of the money rows, because those colours belong to money
/// that moved.
class DeltaLine extends StatelessWidget {
  const DeltaLine({
    super.key,
    required this.what,
    required this.delta,
    required this.comparison,
    required this.symbol,
  });

  /// "Spent" or "Received", for the screen reader.
  final String what;
  final Delta delta;
  final Comparison comparison;
  final String symbol;

  /// "Sep" for a finished month, otherwise the compared dates.
  String get _label {
    final prev = comparison.previous;
    final year = comparison.current.start.year;
    if (comparison.kind == ComparisonKind.month && !comparison.paceMatched) {
      final month = _months[prev.start.month - 1];
      return prev.start.year == year ? month : '$month ${prev.start.year}';
    }
    return formatShortRange(prev, relativeToYear: year);
  }

  String get _spokenLabel =>
      _label.replaceAll(' – ', ' to ').replaceAll('–', ' to ');

  String get _glyph => switch (delta.direction) {
    DeltaDirection.up => '▲',
    DeltaDirection.down => '▼',
    DeltaDirection.same => '=',
  };

  String get _body {
    if (delta.direction == DeltaDirection.same) return 'about the same';
    if (delta.fromNothing) {
      return formatMoney(delta.cents, symbol, showPlus: true);
    }
    return '${delta.percent}%${delta.capped ? '+' : ''}';
  }

  String get _spoken {
    final label = _spokenLabel;
    final size = formatMoney(delta.cents, symbol);
    switch (delta.direction) {
      case DeltaDirection.same:
        return '$what about the same as $label.';
      case DeltaDirection.up:
        return delta.fromNothing
            ? '$what $size, compared with nothing in $label.'
            : '$what ${delta.percent}% more than $label, $size more.';
      case DeltaDirection.down:
        return '$what ${delta.percent}% less than $label, $size less.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Semantics(
      label: _spoken,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Gap.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$_glyph $_body vs $_label',
                style: monoText(size: 12, color: c.dim, letterSpacing: 0.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
