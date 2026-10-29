/// Every playful string in one place. With Lab flavor on, empty states and
/// section names use instrument wording; off, they read plainly. The look is
/// identical either way. Keeping the strings together is also what makes the
/// app ready to translate later.
class Copy {
  const Copy({required this.lab});

  final bool lab;

  String get emptyRecent => lab
      ? 'Flat line.\nLog your first transaction.'
      : 'No transactions yet.\nTap + to add one.';

  String get emptyHistory => lab
      ? 'Flat line.\nNothing logged yet.'
      : 'No transactions yet.\nTap + to add one.';

  String get emptyChart => lab
      ? 'Flat line. Nothing spent in this period.'
      : 'Nothing spent in this period.';

  /// History search found nothing.
  String noMatches(String query) => lab
      ? 'Flat line.\nNothing matches “$query”.'
      : 'No matches for “$query”.';

  String get chartTitle => lab ? 'Spectrum' : 'Spending';

  /// The trace has nothing to draw.
  String get emptyTrends => lab
      ? 'Flat line. Log a few transactions to see a trace.'
      : 'Nothing logged in these months yet.';

  /// The month-end page, and the list of earlier ones under Trends.
  String get reportTitle => lab ? 'Lab report' : 'Month in review';
  String get reportsLabel => lab ? 'Lab reports' : 'Monthly reviews';

  /// The Home card announcing it; [month] is a month name such as `September`.
  String reportReady(String month) =>
      lab ? 'Your $month lab report is ready' : 'Your $month review is ready';

  /// The name of a goal's progress readout (saved over target).
  String get goalYield => lab ? 'YIELD' : 'SAVED';

  /// Insights: nothing to save towards yet.
  String get emptyGoals => lab
      ? 'Nothing in the flask yet. Set a goal to start filling it.'
      : 'No goals yet. Set one to start saving towards it.';

  /// The name of the share of income kept, on its own.
  String get purityName => lab ? 'PURITY' : 'SAVED';

  /// The share of income kept, month by month.
  String get purityByMonth => lab ? 'PURITY by month' : 'Saved by month';

  /// Under the balance: the share of income you kept. Lab flavor calls it
  /// PURITY; plain wording says SAVED.
  String purity(String percent) => lab ? 'PURITY $percent' : 'SAVED $percent';
}
