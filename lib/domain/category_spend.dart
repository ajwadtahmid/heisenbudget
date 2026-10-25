// PURE DART: the numbers behind the spending chart and the PURITY readout.

/// What was spent in one category over a period.
class CategorySpend {
  const CategorySpend({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.cents,
  });

  final int categoryId;
  final String name;

  /// A key from `categoryIcons`.
  final String icon;
  final int cents;
}

/// One bar in the spending chart.
class SpectrumBar {
  const SpectrumBar({
    required this.label,
    required this.iconKey,
    required this.cents,
    required this.permille,
    this.isRest = false,
  });

  final String label;
  final String iconKey;
  final int cents;

  /// Share of all spending in tenths of a percent (624 means 62.4%).
  final int permille;

  /// True for the combined "Rest" bar.
  final bool isRest;

  /// Whole percent for the bar label: `62%`.
  String get percentText => '${(permille / 10).round()}%';

  /// One decimal for the readout line: `62.4%`.
  String get percentDetailText => '${permille ~/ 10}.${permille % 10}%';
}

/// The chart's bars: the [top] biggest categories, then everything else
/// folded into one "Rest" bar. Input must be sorted biggest first.
List<SpectrumBar> buildSpectrum(
  List<CategorySpend> spends, {
  int top = 5,
  String restLabel = 'Rest',
  String restIcon = 'more',
}) {
  final total = spends.fold<int>(0, (sum, s) => sum + s.cents);
  if (total <= 0) return const [];

  // Rounded to the nearest tenth of a percent, in integers.
  int share(int cents) => (cents * 1000 + total ~/ 2) ~/ total;

  final shown = spends.take(top).toList();
  final bars = [
    for (final s in shown)
      SpectrumBar(
        label: s.name,
        iconKey: s.icon,
        cents: s.cents,
        permille: share(s.cents),
      ),
  ];

  final restCents = spends.skip(top).fold<int>(0, (sum, s) => sum + s.cents);
  if (restCents > 0) {
    bars.add(
      SpectrumBar(
        label: restLabel,
        iconKey: restIcon,
        cents: restCents,
        permille: share(restCents),
        isRest: true,
      ),
    );
  }
  return bars;
}

/// PURITY: the share of what came in that you kept, in tenths of a percent
/// (0 to 1000). Null when nothing came in (nothing to measure). Overspending
/// reads as 0.0%, never negative.
int? purityPermille(int receivedCents, int spentCents) {
  if (receivedCents <= 0) return null;
  final kept = receivedCents - spentCents;
  if (kept <= 0) return 0;
  return (kept * 1000 + receivedCents ~/ 2) ~/ receivedCents;
}

/// `95.0%`
String purityText(int permille) => '${permille ~/ 10}.${permille % 10}%';
