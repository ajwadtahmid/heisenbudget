import '../../core/formatters.dart';
import '../../domain/transaction_type.dart';
import '../repositories/transaction_repository.dart';

/// Transactions as CSV for spreadsheets:
/// `Date,Type,Category,Title,Amount,Note`.
///
/// Amounts are plain positive decimals with a dot (`12.50`) whatever the
/// phone's language, and the type column says income or expense. The text
/// starts with a byte-order mark so Excel reads symbols such as `৳` right.
String buildTransactionsCsv(List<TransactionWithCategory> rows) {
  final out = StringBuffer('﻿')
    ..write(
      _line(const ['Date', 'Type', 'Category', 'Title', 'Amount', 'Note']),
    );
  for (final row in rows) {
    final t = row.transaction;
    out.write(
      _line([
        t.date,
        t.type == TransactionType.income ? 'Income' : 'Expense',
        _safe(row.category.name),
        _safe(t.title ?? ''),
        centsToInputText(t.amountCents),
        _safe(t.note ?? ''),
      ]),
    );
  }
  return out.toString();
}

String _line(List<String> cells) => '${cells.map(_cell).join(',')}\r\n';

/// Quotes a cell when it holds a comma, quote or line break.
String _cell(String value) {
  if (!value.contains(RegExp(r'[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// A cell that starts with `=`, `+`, `-`, `@`, a tab or a return is read as a
/// formula by Excel and Sheets, so a note like `=HYPERLINK(...)` could run
/// when the file is opened. A leading apostrophe makes it plain text.
String _safe(String value) =>
    value.startsWith(RegExp(r'[=+\-@\t\r]')) ? "'$value" : value;
