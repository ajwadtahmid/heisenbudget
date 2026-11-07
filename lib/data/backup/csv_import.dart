import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../../core/constants.dart';
import '../../core/money_parser.dart';
import '../../domain/transaction_type.dart';
import 'backup_data.dart' show BackupFormatException;

/// The biggest file the importer opens, and the most rows it reads at once.
const maxCsvBytes = 16 * 1024 * 1024;
const maxImportRows = 20000;

/// The text of a file, and whether the encoding had to be guessed.
class CsvText {
  const CsvText(this.text, {this.guessedEncoding = false});

  final String text;

  /// The file was not valid UTF-8 and was read as Windows-1252/Latin-1, so
  /// accents or symbols may look wrong.
  final bool guessedEncoding;
}

/// Turns a picked file into text, or says in plain words why it cannot be one.
/// Reads UTF-8 (with or without a byte-order mark) and UTF-16 (what Excel's
/// "Unicode text" makes); anything else that is still text is read as
/// Latin-1.
CsvText decodeCsvBytes(Uint8List bytes) {
  const notText = BackupFormatException(
    'That does not look like a text file. Choose a .csv file.',
  );
  if (bytes.isEmpty) throw const BackupFormatException('That file is empty.');
  if (bytes.length > maxCsvBytes) {
    throw const BackupFormatException(
      'That file is too large to import. Split it into smaller parts.',
    );
  }
  String text;
  var guessed = false;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = _utf16(bytes, Endian.little);
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = _utf16(bytes, Endian.big);
  } else {
    if (bytes.contains(0)) throw notText;
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    final body = bytes.sublist(start);
    try {
      text = utf8.decode(body);
    } on FormatException {
      text = latin1.decode(body);
      guessed = true;
    }
  }
  if (text.trim().isEmpty) {
    throw const BackupFormatException('That file is empty.');
  }
  // Mostly control characters means a picture, a PDF or a zip, not text.
  var controls = 0;
  for (final unit in text.codeUnits) {
    if (unit < 32 && unit != 9 && unit != 10 && unit != 13) controls++;
  }
  if (controls > text.length * 0.02) throw notText;
  final head = text.trimLeft();
  if (head.startsWith('{') || head.startsWith('[')) {
    throw const BackupFormatException(
      'This is a JSON file, not a CSV. If it is a Heisenbudget backup, use '
      'Restore from backup instead.',
    );
  }
  return CsvText(text, guessedEncoding: guessed);
}

String _utf16(Uint8List bytes, Endian endian) {
  final data = ByteData.sublistView(bytes);
  final units = <int>[];
  for (var i = 2; i + 1 < bytes.length; i += 2) {
    units.add(data.getUint16(i, endian));
  }
  return String.fromCharCodes(units);
}

/// Rows of cells, and the physical line each row started on.
class CsvTable {
  const CsvTable(this.rows, this.lines, this.delimiter);

  final List<List<String>> rows;
  final List<int> lines;
  final String delimiter;
}

/// Reads CSV text: quoted cells (with `""` for a quote and line breaks inside),
/// `,` `;` or tab between cells (chosen from the first line), and any of CRLF,
/// LF or CR between rows. Empty lines are skipped. Throws
/// [BackupFormatException] when a quoted cell is never closed.
CsvTable parseCsv(String text) {
  final delimiter = _detectDelimiter(text);
  final rows = <List<String>>[];
  final lines = <int>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var cellQuoted = false;
  var line = 1;
  var rowLine = 1;
  var quoteLine = 1;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
    cellQuoted = false;
  }

  void endRow() {
    endCell();
    final empty = row.length == 1 && row.first.trim().isEmpty;
    if (!empty) {
      rows.add(row);
      lines.add(rowLine);
    }
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        if (ch == '\n') line++;
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && cell.isEmpty && !cellQuoted) {
      inQuotes = true;
      cellQuoted = true;
      quoteLine = line;
    } else if (ch == delimiter) {
      endCell();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
      line++;
      rowLine = line;
    } else {
      cell.write(ch);
    }
  }
  if (inQuotes) {
    throw BackupFormatException(
      'The file looks damaged: a quoted value that starts on line $quoteLine '
      'is never closed.',
    );
  }
  if (cell.isNotEmpty || cellQuoted || row.isNotEmpty) endRow();
  return CsvTable(rows, lines, delimiter);
}

/// [parseCsv], off the main thread for a big file so the screen stays alive.
Future<CsvTable> parseCsvInBackground(String text) {
  if (text.length < 300000) return Future.value(parseCsv(text));
  return compute(parseCsv, text);
}

String _detectDelimiter(String text) {
  var firstLine = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') inQuotes = !inQuotes;
    if (!inQuotes && (ch == '\n' || ch == '\r')) {
      if (firstLine.toString().trim().isNotEmpty) break;
      firstLine = StringBuffer();
      continue;
    }
    if (!inQuotes) firstLine.write(ch);
  }
  final head = firstLine.toString();
  var best = ',';
  var bestCount = 0;
  for (final d in const [',', ';', '\t']) {
    final n = d.allMatches(head).length;
    if (n > bestCount) {
      best = d;
      bestCount = n;
    }
  }
  return best;
}

/// The order the parts of a day-first/month-first date come in.
enum DateOrder {
  ymd('Year, month, day'),
  dmy('Day, month, year'),
  mdy('Month, day, year');

  const DateOrder(this.label);
  final String label;
}

/// Which column holds what. A column is a 0-based index into a row, or null.
/// Either [amount] (one column, signed or with a [type] column) or
/// [moneyOut] and [moneyIn] (a bank's separate columns) gives the amount.
class CsvMapping {
  CsvMapping({
    this.hasHeader = true,
    this.date,
    this.amount,
    this.type,
    this.category,
    this.title,
    this.note,
    this.moneyOut,
    this.moneyIn,
    this.order = DateOrder.ymd,
    this.positiveIsExpense = false,
  });

  bool hasHeader;
  int? date;
  int? amount;
  int? type;
  int? category;
  int? title;
  int? note;
  int? moneyOut;
  int? moneyIn;
  DateOrder order;

  /// With a single signed amount column and no type column: positive numbers
  /// are spending (card statements often show purchases that way).
  bool positiveIsExpense;

  bool get hasAmount => amount != null || moneyOut != null || moneyIn != null;

  /// Enough to read rows: a date and an amount.
  bool get isComplete => date != null && hasAmount;
}

const _dateNames = [
  'date',
  'day',
  'posted',
  'transaction date',
  'booking date',
];
const _amountNames = ['amount', 'value', 'sum', 'total'];
const _typeNames = ['type', 'kind', 'direction'];
const _categoryNames = ['category', 'group', 'tag'];
const _titleNames = ['title', 'payee', 'merchant', 'description', 'name'];
const _noteNames = ['note', 'notes', 'memo', 'details', 'comment', 'reference'];
const _outNames = ['money out', 'debit', 'withdrawal', 'paid out', 'out'];
const _inNames = ['money in', 'credit', 'deposit', 'paid in', 'in'];

/// A first guess at the columns, from the header names (and, when there are
/// none, from what the cells look like). The person can change every choice.
CsvMapping guessMapping(CsvTable table) {
  final first = table.rows.first;
  final hasHeader = !first.any(_looksLikeData);
  final m = CsvMapping(hasHeader: hasHeader);
  final used = <int>{};
  int? find(List<String> names) {
    if (!hasHeader) return null;
    for (var i = 0; i < first.length; i++) {
      if (used.contains(i)) continue;
      if (names.contains(first[i].trim().toLowerCase())) {
        used.add(i);
        return i;
      }
    }
    return null;
  }

  m.date = find(_dateNames);
  m.amount = find(_amountNames);
  m.type = find(_typeNames);
  m.category = find(_categoryNames);
  m.title = find(_titleNames);
  m.note = find(_noteNames);
  if (m.amount == null) {
    m.moneyOut = find(_outNames);
    m.moneyIn = find(_inNames);
  }

  final data = table.rows.skip(hasHeader ? 1 : 0).take(50).toList();
  int? bestColumn(bool Function(String) test, Set<int> skip) {
    final width = data.fold<int>(0, (w, r) => r.length > w ? r.length : w);
    int? best;
    var bestHits = 0;
    for (var c = 0; c < width; c++) {
      if (skip.contains(c)) continue;
      var hits = 0, seen = 0;
      for (final r in data) {
        if (c < r.length && r[c].trim().isNotEmpty) {
          seen++;
          if (test(r[c])) hits++;
        }
      }
      if (seen > 0 && hits / seen >= 0.6 && hits > bestHits) {
        best = c;
        bestHits = hits;
      }
    }
    return best;
  }

  m.date ??= bestColumn(_isDateLike, used);
  if (m.date != null) used.add(m.date!);
  if (!m.hasAmount) {
    m.amount = bestColumn((s) => _parseAmount(s).cents != null, used);
  }

  final samples = [
    if (m.date != null)
      for (final r in data)
        if (m.date! < r.length) r[m.date!],
  ];
  m.order = _guessOrder(samples);
  return m;
}

bool _looksLikeData(String cell) {
  final s = cell.trim();
  if (s.isEmpty) return false;
  return _isDateLike(s) ||
      (RegExp(r'^[\d\s.,+\-()$€£¥]+$').hasMatch(s) &&
          RegExp(r'\d').hasMatch(s));
}

final _isoDate = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$');
final _partsDate = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$');
final _dayMonthName = RegExp(
  r'^(\d{1,2})[ \-]([A-Za-z]{3,9})\.?,?[ \-](\d{4})$',
);
final _monthNameDay = RegExp(r'^([A-Za-z]{3,9})\.? (\d{1,2}),? (\d{4})$');

String _dateOnlyText(String raw) {
  final s = raw.trim();
  final cut = s.indexOf(RegExp(r'T|\s\d{1,2}:'));
  return (cut > 0 ? s.substring(0, cut) : s).trim();
}

bool _isDateLike(String raw) {
  final s = _dateOnlyText(raw);
  return _isoDate.hasMatch(s) ||
      _partsDate.hasMatch(s) ||
      _dayMonthName.hasMatch(s) ||
      _monthNameDay.hasMatch(s);
}

DateOrder _guessOrder(List<String> samples) {
  var firstOver12 = false, secondOver12 = false, dots = false;
  for (final raw in samples) {
    final s = _dateOnlyText(raw);
    if (_isoDate.hasMatch(s)) return DateOrder.ymd;
    final m = _partsDate.firstMatch(s);
    if (m == null) continue;
    if (int.parse(m.group(1)!) > 12) firstOver12 = true;
    if (int.parse(m.group(2)!) > 12) secondOver12 = true;
    if (s.contains('.')) dots = true;
  }
  if (firstOver12 && !secondOver12) return DateOrder.dmy;
  if (secondOver12 && !firstOver12) return DateOrder.mdy;
  // Ambiguous: dots are day-first in practice; slashes default to month-first.
  return dots ? DateOrder.dmy : DateOrder.mdy;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// A date in the stated [order] (month names work in any order), or null when
/// it is not a real date or is outside the years the app stores.
DateTime? parseImportDate(String raw, DateOrder order) {
  final s = _dateOnlyText(raw);
  int? y, mo, d;
  final iso = _isoDate.firstMatch(s);
  final parts = _partsDate.firstMatch(s);
  final named1 = _dayMonthName.firstMatch(s);
  final named2 = _monthNameDay.firstMatch(s);
  if (iso != null) {
    y = int.parse(iso.group(1)!);
    mo = int.parse(iso.group(2)!);
    d = int.parse(iso.group(3)!);
  } else if (parts != null) {
    final a = int.parse(parts.group(1)!);
    final b = int.parse(parts.group(2)!);
    var year = int.parse(parts.group(3)!);
    if (parts.group(3)!.length == 2) year += 2000;
    y = year;
    if (order == DateOrder.mdy) {
      mo = a;
      d = b;
    } else {
      d = a;
      mo = b;
    }
  } else if (named1 != null) {
    d = int.parse(named1.group(1)!);
    mo = _months[named1.group(2)!.toLowerCase().substring(0, 3)];
    y = int.parse(named1.group(3)!);
  } else if (named2 != null) {
    mo = _months[named2.group(1)!.toLowerCase().substring(0, 3)];
    d = int.parse(named2.group(2)!);
    y = int.parse(named2.group(3)!);
  }
  if (y == null || mo == null || d == null) return null;
  if (y < minDataYear || y > maxDataYear) return null;
  if (mo < 1 || mo > 12 || d < 1) return null;
  final date = DateTime(y, mo, d);
  return date.month == mo && date.day == d ? date : null;
}

/// A signed amount in cents from text such as `12.50`, `-12.50`, `(12.50)`,
/// `$1,234.56`, `12.50-` or `1.234,56 €`, or an error message.
({int? cents, String? error}) _parseAmount(String raw) {
  var s = raw.trim().replaceAll('−', '-');
  if (s.isEmpty) return (cents: null, error: 'There is no amount');
  final negative = s.contains('-') || (s.startsWith('(') && s.endsWith(')'));
  s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (s.isEmpty) {
    return (cents: null, error: 'The amount "${raw.trim()}" is not a number');
  }
  final parsed = parseMoney(s);
  if (parsed.cents == null) {
    final message = parsed.error == errorNotPositive
        ? 'The amount is zero'
        : parsed.error == errorTooLarge
        ? 'The amount is too large'
        : 'The amount "${raw.trim()}" is not a number';
    return (cents: null, error: message);
  }
  return (cents: negative ? -parsed.cents! : parsed.cents, error: null);
}

TransactionType? _typeOf(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'in' ||
      s == '+' ||
      s.startsWith('inc') ||
      s.startsWith('cr') ||
      s.startsWith('dep') ||
      s.startsWith('rec')) {
    return TransactionType.income;
  }
  if (s == 'out' ||
      s == '-' ||
      s == 'dr' ||
      s.startsWith('exp') ||
      s.startsWith('deb') ||
      s.startsWith('wit') ||
      s.startsWith('pay') ||
      s.startsWith('spe')) {
    return TransactionType.expense;
  }
  return null;
}

/// One data row of the file, read, or with the reason it could not be.
class ImportRow {
  const ImportRow({
    required this.line,
    this.date,
    this.cents,
    this.type,
    this.category,
    this.title = '',
    this.note = '',
    this.shortened = false,
    this.error,
  });

  /// The line of the file the row started on.
  final int line;
  final DateTime? date;
  final int? cents;
  final TransactionType? type;
  final String? category;
  final String title;
  final String note;

  /// A title or name was longer than the app keeps and was cut short.
  final bool shortened;
  final String? error;

  bool get ok => error == null;
}

/// Our own CSV export puts an apostrophe before a cell that would be read as a
/// formula (`=`, `+`, `-`, `@`); it is taken off again here.
String _plain(String cell) {
  final s = cell.trim();
  return s.length > 1 && s.startsWith("'") && RegExp(r'[=+\-@]').hasMatch(s[1])
      ? s.substring(1)
      : s;
}

/// Reads every data row with [m]. A row that cannot be read keeps its [error]
/// instead of stopping the rest. Throws [BackupFormatException] when there are
/// no data rows or too many.
List<ImportRow> readRows(CsvTable table, CsvMapping m) {
  final start = m.hasHeader ? 1 : 0;
  final count = table.rows.length - start;
  if (count <= 0) {
    throw const BackupFormatException(
      'The file has no transactions, only a first row.',
    );
  }
  if (count > maxImportRows) {
    throw BackupFormatException(
      'This file has $count rows. Import up to $maxImportRows at a time: '
      'split it into smaller files.',
    );
  }
  String cell(List<String> row, int? c) =>
      c == null || c >= row.length ? '' : row[c];

  final out = <ImportRow>[];
  for (var i = start; i < table.rows.length; i++) {
    final row = table.rows[i];
    final line = table.lines[i];
    ImportRow fail(String why) => ImportRow(line: line, error: why);

    final date = parseImportDate(cell(row, m.date), m.order);
    if (date == null) {
      final raw = cell(row, m.date).trim();
      out.add(
        fail(
          raw.isEmpty
              ? 'There is no date'
              : 'The date "$raw" could not be read with this date order',
        ),
      );
      continue;
    }

    int cents;
    TransactionType type;
    if (m.amount != null) {
      final a = _parseAmount(cell(row, m.amount));
      if (a.cents == null) {
        out.add(fail(a.error!));
        continue;
      }
      final negative = a.cents! < 0;
      cents = a.cents!.abs();
      final typeText = cell(row, m.type).trim();
      final named = m.type == null ? null : _typeOf(typeText);
      if (m.type != null && named == null && typeText.isNotEmpty) {
        out.add(fail('The type "$typeText" is not income or expense'));
        continue;
      }
      if (named != null) {
        type = named;
      } else if (m.type != null && !negative && !m.positiveIsExpense) {
        out.add(fail('It is not clear if this is income or expense'));
        continue;
      } else {
        type = (negative != m.positiveIsExpense)
            ? TransactionType.expense
            : TransactionType.income;
      }
    } else {
      final outText = cell(row, m.moneyOut).trim();
      final inText = cell(row, m.moneyIn).trim();
      final o = outText.isEmpty ? null : _parseAmount(outText);
      final n = inText.isEmpty ? null : _parseAmount(inText);
      final oValue = o?.cents?.abs();
      final nValue = n?.cents?.abs();
      if (o?.error != null && o!.error != 'The amount is zero') {
        out.add(fail(o.error!));
        continue;
      }
      if (n?.error != null && n!.error != 'The amount is zero') {
        out.add(fail(n.error!));
        continue;
      }
      if (oValue != null && nValue != null) {
        out.add(fail('Both money out and money in are filled'));
        continue;
      }
      final value = oValue ?? nValue;
      if (value == null) {
        out.add(fail(o?.error ?? n?.error ?? 'There is no amount'));
        continue;
      }
      cents = value;
      type = oValue != null ? TransactionType.expense : TransactionType.income;
    }

    var title = _plain(cell(row, m.title));
    var note = _plain(cell(row, m.note));
    var shortened = false;
    if (title.length > maxTitleLength) {
      shortened = true;
      if (note.isEmpty) note = title;
      title = title.substring(0, maxTitleLength).trimRight();
    }
    if (note.length > maxNoteLength) {
      shortened = true;
      note = note.substring(0, maxNoteLength).trimRight();
    }
    var category = _plain(cell(row, m.category));
    if (category.length > maxCategoryNameLength) {
      shortened = true;
      category = category.substring(0, maxCategoryNameLength).trimRight();
    }
    out.add(
      ImportRow(
        line: line,
        date: date,
        cents: cents,
        type: type,
        category: category.isEmpty ? null : category,
        title: title,
        note: note,
        shortened: shortened,
      ),
    );
  }
  return out;
}
