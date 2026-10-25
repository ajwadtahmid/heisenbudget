/// Totals for a period, in cents.
class Summary {
  const Summary({required this.receivedCents, required this.spentCents});

  static const empty = Summary(receivedCents: 0, spentCents: 0);

  final int receivedCents;
  final int spentCents;

  int get netCents => receivedCents - spentCents;

  @override
  bool operator ==(Object other) =>
      other is Summary &&
      other.receivedCents == receivedCents &&
      other.spentCents == spentCents;

  @override
  int get hashCode => Object.hash(receivedCents, spentCents);
}
