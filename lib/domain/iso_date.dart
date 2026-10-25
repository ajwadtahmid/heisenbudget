// Dates are stored as date-only ISO text (`yyyy-MM-dd`), which sorts and
// compares correctly in SQL and has no timezone or DST problems.

/// Strips the time of day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `2026-10-05`
String toIsoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Inverse of [toIsoDate].
DateTime fromIsoDate(String s) {
  final parts = s.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
