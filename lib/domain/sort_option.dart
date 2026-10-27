/// How the History list is ordered.
enum SortOption {
  newestFirst('Date: newest first'),
  oldestFirst('Date: oldest first'),
  highestAmount('Amount: highest first'),
  lowestAmount('Amount: lowest first');

  const SortOption(this.label);
  final String label;

  /// Ordered by date, so rows of one day sit together (History groups them).
  bool get isByDate => this == newestFirst || this == oldestFirst;
}
