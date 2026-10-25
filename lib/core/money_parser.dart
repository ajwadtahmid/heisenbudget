import 'constants.dart';

/// The outcome of reading an amount the user typed. Exactly one of [cents]
/// and [error] is set.
class MoneyParseResult {
  const MoneyParseResult.ok(int this.cents) : error = null;
  const MoneyParseResult.error(String this.error) : cents = null;

  final int? cents;
  final String? error;

  bool get isValid => cents != null;
}

const errorEmptyAmount = 'Enter an amount';
const errorInvalidAmount = 'Enter a valid amount';
const errorNotPositive = 'Amount must be greater than zero';
const errorTooManyDecimals = 'Use at most 2 decimal places';
const errorThousandsSeparator = 'Enter the amount without thousands separators';
const errorTooLarge = 'Amount is too large';

/// Reads text such as `12`, `12.5`, `12.50` or `12,50` into integer cents.
///
/// Spaces are ignored. Thousands separators (`1,234.56`) are rejected on
/// purpose: `1,234` could mean 1.234 or 1234. A single comma followed by one
/// or two digits is read as a decimal comma.
///
/// By default the amount must be greater than zero. The starting balance
/// passes [allowNegative] and [allowZero].
MoneyParseResult parseMoney(
  String text, {
  bool allowNegative = false,
  bool allowZero = false,
}) {
  var s = text.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return const MoneyParseResult.error(errorEmptyAmount);

  var negative = false;
  if (s.startsWith('-')) {
    if (!allowNegative) return const MoneyParseResult.error(errorNotPositive);
    negative = true;
    s = s.substring(1);
    if (s.isEmpty) return const MoneyParseResult.error(errorInvalidAmount);
  }

  final commas = ','.allMatches(s).length;
  final dots = '.'.allMatches(s).length;
  if (commas > 1 || (commas == 1 && dots > 0)) {
    return const MoneyParseResult.error(errorThousandsSeparator);
  }
  if (commas == 1) {
    final afterComma = s.length - s.indexOf(',') - 1;
    if (afterComma == 3) {
      return const MoneyParseResult.error(errorThousandsSeparator);
    }
    s = s.replaceAll(',', '.');
  }

  if (!RegExp(r'^\d*\.?\d*$').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
    return const MoneyParseResult.error(errorInvalidAmount);
  }

  final parts = s.split('.');
  final wholeText = parts[0].isEmpty ? '0' : parts[0];
  final fractionText = parts.length > 1 ? parts[1] : '';
  if (fractionText.length > 2) {
    return const MoneyParseResult.error(errorTooManyDecimals);
  }
  // 12 digits is already above the maximum; stops int overflow on huge input.
  if (wholeText.length > 12) {
    return const MoneyParseResult.error(errorTooLarge);
  }

  final cents =
      int.parse(wholeText) * 100 + int.parse(fractionText.padRight(2, '0'));
  if (cents > maxAmountCents) {
    return const MoneyParseResult.error(errorTooLarge);
  }
  if (cents == 0 && !allowZero) {
    return const MoneyParseResult.error(errorNotPositive);
  }
  return MoneyParseResult.ok(negative ? -cents : cents);
}
