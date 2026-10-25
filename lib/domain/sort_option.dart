/// How the History list is ordered.
enum SortOption {
  newestFirst('Date: newest first'),
  oldestFirst('Date: oldest first'),
  highestAmount('Amount: highest first'),
  lowestAmount('Amount: lowest first');

  const SortOption(this.label);
  final String label;
}
