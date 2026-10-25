import 'package:intl/intl.dart';

import '../domain/date_range.dart';

/// `$12.50`, `-$12.50`, `+$12.50`. Works on integer cents, never a double.
/// A symbol that ends in a letter (e.g. `Rs`) gets a space: `Rs 12.50`.
String formatMoney(int cents, String symbol, {bool showPlus = false}) {
  final sign = cents < 0 ? '-' : (showPlus && cents > 0 ? '+' : '');
  final abs = cents.abs();
  final grouping = NumberFormat.decimalPattern();
  final whole = grouping.format(abs ~/ 100);
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final endsWithLetter = RegExp(r'\p{L}$', unicode: true).hasMatch(symbol);
  final gap = endsWithLetter ? ' ' : '';
  return '$sign$symbol$gap$whole${grouping.symbols.DECIMAL_SEP}$fraction';
}

/// Plain decimal text for an amount field: `1250` -> `12.50`.
String centsToInputText(int cents) {
  final abs = cents.abs();
  final sign = cents < 0 ? '-' : '';
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// `Oct 5, 2026`
String formatDate(DateTime d) => DateFormat.yMMMd().format(d);

/// `Mon, Oct 5, 2026`
String formatDayHeader(DateTime d) => DateFormat.yMMMEd().format(d);

/// `October 2026`
String formatMonth(DateTime d) => DateFormat.yMMMM().format(d);

/// `Oct 1 – Oct 7, 2026`, or with both years when the range crosses a year.
String formatRange(DateRange range) {
  final start = range.start;
  final end = range.end;
  if (start == end) return formatDate(start);
  if (start.year == end.year) {
    final md = DateFormat.MMMd();
    return '${md.format(start)} – ${md.format(end)}, ${end.year}';
  }
  return '${formatDate(start)} – ${formatDate(end)}';
}
