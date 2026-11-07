import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/backup/backup_data.dart' show BackupFormatException;
import '../../data/backup/csv_import.dart';
import '../../data/backup/csv_importer.dart';
import '../../domain/transaction_type.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_providers.dart';

/// Opens the import page for a file that has been read, and returns what was
/// imported (null when the person backed out).
Future<ImportResult?> openCsvImport(
  BuildContext context,
  CsvTable table, {
  bool guessedEncoding = false,
}) {
  return Navigator.of(context).push<ImportResult>(
    MaterialPageRoute(
      builder: (_) =>
          CsvImportScreen(table: table, guessedEncoding: guessedEncoding),
    ),
  );
}

/// Choose which column is which, see what would be added (and what cannot be
/// read), then import. Nothing is written until Import is pressed.
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({
    super.key,
    required this.table,
    this.guessedEncoding = false,
  });

  final CsvTable table;
  final bool guessedEncoding;

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  late final CsvMapping _m = guessMapping(widget.table);
  bool _createCategories = true;
  bool _skipDuplicates = true;
  bool _busy = false;
  String? _error;

  List<ImportRow>? _rows;
  String? _fileError;
  ImportAnalysis? _analysis;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  int get _width =>
      widget.table.rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);

  String _columnName(int c) {
    final first = widget.table.rows.first;
    final header = _m.hasHeader && c < first.length ? first[c].trim() : '';
    return header.isEmpty ? 'Column ${c + 1}' : header;
  }

  String _sample(int c) {
    final start = _m.hasHeader ? 1 : 0;
    for (var i = start; i < widget.table.rows.length && i < start + 5; i++) {
      final row = widget.table.rows[i];
      if (c < row.length && row[c].trim().isNotEmpty) return row[c].trim();
    }
    return '';
  }

  void _change(void Function() change) {
    setState(() {
      change();
      _error = null;
    });
    _recompute();
  }

  void _recompute() {
    _analysis = null;
    _fileError = null;
    if (!_m.isComplete) {
      _rows = null;
      return;
    }
    try {
      _rows = readRows(widget.table, _m);
    } on BackupFormatException catch (e) {
      _rows = null;
      _fileError = e.message;
      return;
    }
    final token = ++_token;
    ref
        .read(csvImporterProvider)
        .analyze(
          _rows!,
          createCategories: _createCategories,
          skipDuplicates: _skipDuplicates,
        )
        .then((analysis) {
          if (mounted && token == _token) setState(() => _analysis = analysis);
        })
        .catchError((_) {
          if (mounted && token == _token) {
            setState(
              () => _error = 'Could not check the file against your data.',
            );
          }
        });
  }

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(csvImporterProvider)
          .import(
            rows,
            createCategories: _createCategories,
            skipDuplicates: _skipDuplicates,
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not import. Nothing was changed.';
        });
      }
    }
  }

  Widget _picker(
    String label,
    int? value,
    void Function(int?) onChanged, {
    bool required = false,
    String? help,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.m),
      child: DropdownButtonFormField<int?>(
        key: key,
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(
          labelText: required ? '$label (needed)' : label,
          helperText: help,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('None')),
          for (var c = 0; c < _width; c++)
            DropdownMenuItem<int?>(
              value: c,
              child: Text(
                _sample(c).isEmpty
                    ? _columnName(c)
                    : '${_columnName(c)} (${_sample(c)})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => _change(() => onChanged(v)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final rows = _rows;
    final analysis = _analysis;
    final bad = rows?.where((r) => !r.ok).toList() ?? const <ImportRow>[];
    final readable = rows == null ? 0 : rows.length - bad.length;
    final ready = analysis?.toImport.length ?? 0;
    final dataRows = widget.table.rows.length - (_m.hasHeader ? 1 : 0);
    final usesSign = _m.amount != null && _m.type == null;

    // Why nothing can be imported yet, in words.
    String? blocked;
    if (!_m.isComplete) {
      blocked = 'Choose the columns that hold the date and the amount.';
    } else if (_fileError != null) {
      blocked = _fileError;
    } else if (rows != null && readable == 0) {
      blocked =
          'None of the rows could be read. Check the date order and the '
          'columns you chose.';
    } else if (analysis != null && ready == 0) {
      blocked = 'Everything in this file is already here.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Import from CSV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            '$dataRows row${dataRows == 1 ? '' : 's'} found. Check which '
            'column is which, then look over what will be added. Nothing is '
            'saved until you press Import.',
            style: theme.textTheme.bodyMedium,
          ),
          if (widget.guessedEncoding) ...[
            const SizedBox(height: Gap.s),
            Text(
              'This file is not in a standard text encoding. Accents and '
              'symbols may look wrong.',
              key: const ValueKey('csv-encoding-note'),
              style: theme.textTheme.bodySmall?.copyWith(color: c.error),
            ),
          ],
          const SizedBox(height: Gap.m),
          SwitchListTile(
            key: const ValueKey('csv-header'),
            contentPadding: EdgeInsets.zero,
            title: const Text('The first row is a header'),
            value: _m.hasHeader,
            onChanged: (v) => _change(() => _m.hasHeader = v),
          ),
          const SectionLabel('Columns'),
          const SizedBox(height: Gap.m),
          _picker(
            'Date',
            _m.date,
            (v) => _m.date = v,
            required: true,
            key: const ValueKey('csv-date'),
          ),
          if (_m.date != null) ...[
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final order in DateOrder.values)
                  ChoiceChip(
                    key: ValueKey('csv-order-${order.name}'),
                    label: Text(order.label),
                    selected: _m.order == order,
                    onSelected: (_) => _change(() => _m.order = order),
                  ),
              ],
            ),
            const SizedBox(height: Gap.m),
          ],
          _picker(
            'Amount',
            _m.amount,
            (v) => _m.amount = v,
            required: _m.moneyOut == null && _m.moneyIn == null,
            help: 'One column. A minus sign means spending.',
            key: const ValueKey('csv-amount'),
          ),
          if (_m.amount == null) ...[
            _picker(
              'Money out',
              _m.moneyOut,
              (v) => _m.moneyOut = v,
              help: 'Or: a column for spending and one for income.',
              key: const ValueKey('csv-out'),
            ),
            _picker(
              'Money in',
              _m.moneyIn,
              (v) => _m.moneyIn = v,
              key: const ValueKey('csv-in'),
            ),
          ],
          if (_m.amount != null)
            _picker(
              'Type',
              _m.type,
              (v) => _m.type = v,
              help: 'Income or expense, if the file says so.',
              key: const ValueKey('csv-type'),
            ),
          if (usesSign)
            SwitchListTile(
              key: const ValueKey('csv-positive-spending'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Positive amounts are spending'),
              subtitle: const Text(
                'Turn on if purchases are shown as positive numbers.',
              ),
              value: _m.positiveIsExpense,
              onChanged: (v) => _change(() => _m.positiveIsExpense = v),
            ),
          _picker(
            'Category',
            _m.category,
            (v) => _m.category = v,
            key: const ValueKey('csv-category'),
          ),
          _picker(
            'Title',
            _m.title,
            (v) => _m.title = v,
            key: const ValueKey('csv-title'),
          ),
          _picker(
            'Note',
            _m.note,
            (v) => _m.note = v,
            key: const ValueKey('csv-note'),
          ),
          const SectionLabel('Options'),
          SwitchListTile(
            key: const ValueKey('csv-create-categories'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Create categories that do not exist'),
            subtitle: const Text(
              'Otherwise they go to Other. At most $maxImportedCategories new '
              'ones are made.',
            ),
            value: _createCategories,
            onChanged: (v) => _change(() => _createCategories = v),
          ),
          SwitchListTile(
            key: const ValueKey('csv-skip-duplicates'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Skip what is already here'),
            subtitle: const Text(
              'Same date, type, amount and title as a transaction you have.',
            ),
            value: _skipDuplicates,
            onChanged: (v) => _change(() => _skipDuplicates = v),
          ),
          const SizedBox(height: Gap.m),
          const SectionLabel('Preview'),
          const SizedBox(height: Gap.s),
          if (analysis == null && blocked != null)
            Text(
              blocked,
              key: const ValueKey('csv-why'),
              style: theme.textTheme.bodyMedium?.copyWith(color: c.error),
            )
          else if (analysis == null)
            const Padding(
              padding: EdgeInsets.all(Gap.m),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready == 1
                        ? '1 transaction will be added.'
                        : '$ready transactions will be added.',
                    key: const ValueKey('csv-ready'),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (analysis.duplicates > 0)
                    Text(
                      '${analysis.duplicates} already here, skipped.',
                      key: const ValueKey('csv-duplicates'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (analysis.newCategories.isNotEmpty)
                    Text(
                      'New categories: ${analysis.newCategories.join(', ')}.',
                      key: const ValueKey('csv-new-categories'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (analysis.toOther > 0)
                    Text(
                      '${analysis.toOther} will go to Other.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (rows!.any((r) => r.shortened))
                    Text(
                      'Some long titles or names were shortened.',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            if (bad.isNotEmpty) ...[
              const SizedBox(height: Gap.s),
              Text(
                bad.length == 1
                    ? '1 row cannot be read and will be left out.'
                    : '${bad.length} rows cannot be read and will be left out.',
                key: const ValueKey('csv-bad'),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.error),
              ),
              ExpansionTile(
                key: const ValueKey('csv-bad-list'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Show the problems'),
                children: [
                  for (final row in bad.take(20))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Gap.xs),
                        child: Text(
                          'Line ${row.line}: ${row.error}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  if (bad.length > 20)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '…and ${bad.length - 20} more.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
            if (blocked != null) ...[
              const SizedBox(height: Gap.s),
              Text(
                blocked,
                key: const ValueKey('csv-why'),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
              ),
            ],
            if (ready > 0) ...[
              const SizedBox(height: Gap.m),
              Text('The first rows', style: theme.textTheme.labelMedium),
              for (final row in analysis.toImport.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            formatDate(row.date!),
                            if (row.category != null) row.category!,
                            if (row.title.isNotEmpty) row.title,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Gap.s),
                      Text(
                        formatMoney(
                          row.type == TransactionType.income
                              ? row.cents!
                              : -row.cents!,
                          symbol,
                          showPlus: true,
                        ),
                        style: monoText(
                          size: 14,
                          color: row.type == TransactionType.income
                              ? c.received
                              : c.spent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: Gap.m),
            Text(
              _error!,
              key: const ValueKey('csv-error'),
              style: theme.textTheme.bodyMedium?.copyWith(color: c.error),
            ),
          ],
          const SizedBox(height: Gap.l),
          FilledButton(
            key: const ValueKey('csv-import'),
            onPressed: _busy || analysis == null || ready == 0 ? null : _import,
            child: Text(
              _busy
                  ? 'Importing…'
                  : ready == 0
                  ? 'Import'
                  : ready == 1
                  ? 'Import 1 transaction'
                  : 'Import $ready transactions',
            ),
          ),
        ],
      ),
    );
  }
}
