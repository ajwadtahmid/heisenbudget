/// How weeks are counted inside a month.
enum WeekMode {
  /// Blocks of 7 days starting on the 1st: 1-7, 8-14, 15-21, 22-28, 29-end.
  fixed,

  /// Real calendar weeks starting on a chosen weekday, clipped to the month.
  calendar,
}
