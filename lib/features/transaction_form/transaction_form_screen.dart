import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/money_parser.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/iso_date.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/transaction_providers.dart';
import 'new_category_dialog.dart';

/// Opens the Add form, or the Edit form when [editId] is given.
Future<void> showTransactionForm(BuildContext context, {int? editId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TransactionFormSheet(editId: editId),
  );
}

/// The content of the add/edit bottom sheet.
class TransactionFormSheet extends ConsumerWidget {
  const TransactionFormSheet({super.key, this.editId});

  final int? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = editId;
    if (id == null) return const _TransactionForm();

    Widget message(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      child: Center(child: child),
    );

    return ref
        .watch(transactionByIdProvider(id))
        .when(
          data: (item) => item == null
              ? message(const Text('This transaction was deleted.'))
              : _TransactionForm(existing: item),
          loading: () => message(const CircularProgressIndicator()),
          error: (e, _) =>
              message(Text('Could not load this transaction.\n$e')),
        );
  }
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({this.existing});

  final TransactionWithCategory? existing;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late TransactionType _type;
  late DateTime _date;

  /// null = nothing picked yet; the default (last used, else "Other") applies.
  int? _categoryId;
  String? _categoryError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing?.transaction;
    _type = tx?.type ?? TransactionType.expense;
    _date = tx != null ? fromIsoDate(tx.date) : ref.read(clockProvider);
    _categoryId = tx?.categoryId;
    _amount = TextEditingController(
      text: tx != null ? centsToInputText(tx.amountCents) : '',
    );
    _note = TextEditingController(text: tx?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The category that is (or will be) selected for the current type.
  int? _selectedCategory(List<CategoryRow> active) {
    final picked = _categoryId;
    if (picked != null) return picked;
    final lastUsed = ref.read(settingsProvider).lastCategoryFor(_type);
    if (lastUsed != null && active.any((c) => c.id == lastUsed)) {
      return lastUsed;
    }
    for (final c in active) {
      if (c.isProtected) return c.id;
    }
    return active.isEmpty ? null : active.first.id;
  }

  void _setType(TransactionType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _categoryId = null; // a category belongs to one type only
      _categoryError = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _addCategory() async {
    final created = await showCategoryNameDialog(context, type: _type);
    if (created != null && mounted) {
      setState(() {
        _categoryId = created.id;
        _categoryError = null;
      });
    }
  }

  Future<void> _save(List<CategoryRow> active) async {
    if (_saving) return;
    final categoryId = _selectedCategory(active);
    setState(
      () => _categoryError = categoryId == null ? 'Pick a category' : null,
    );
    if (!_formKey.currentState!.validate() || categoryId == null) return;

    setState(() => _saving = true);
    final repo = ref.read(transactionRepositoryProvider);
    final input = TransactionInput(
      amountCents: parseMoney(_amount.text).cents!,
      type: _type,
      date: _date,
      categoryId: categoryId,
      note: _note.text,
    );
    final existing = widget.existing;
    if (existing == null) {
      await repo.add(input);
    } else {
      await repo.update(existing.transaction.id, input);
    }
    await ref
        .read(settingsProvider.notifier)
        .setLastCategory(_type, categoryId);
    HapticFeedback.lightImpact();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(transactionRepositoryProvider)
        .delete(widget.existing!.transaction.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final active = ref.watch(activeCategoriesProvider(_type)).value ?? const [];
    final all = ref.watch(allCategoriesProvider).value ?? const [];
    final selected = _selectedCategory(active);

    // The category being edited may be archived: keep showing it, marked.
    final chips = [...active];
    if (selected != null && !chips.any((c) => c.id == selected)) {
      final archived = all.where((c) => c.id == selected && c.type == _type);
      chips.addAll(archived);
    }

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isEdit ? 'Edit transaction' : 'Add transaction',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_isEdit)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _confirmDelete,
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  SegmentedButton<TransactionType>(
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text('Expense'),
                        icon: Icon(Icons.arrow_upward),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text('Income'),
                        icon: Icon(Icons.arrow_downward),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => _setType(s.first),
                  ),
                  const SizedBox(height: 16),
                  ClampedTextScale(
                    child: TextFormField(
                      key: const ValueKey('amount-field'),
                      controller: _amount,
                      autofocus: !_isEdit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                      ],
                      // The thing being measured: a large mono readout.
                      style: monoText(
                        size: 32,
                        weight: FontWeight.w600,
                        color: context.appColors.text,
                      ),
                      cursorHeight: 30,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '$symbol ',
                        prefixStyle: monoText(
                          size: 32,
                          weight: FontWeight.w500,
                          color: context.appColors.dim,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                      validator: (value) => parseMoney(value ?? '').error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    key: const ValueKey('date-tile'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date'),
                    subtitle: Text(formatDate(_date)),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Category',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    // Chips keep a 48dp touch target, which already adds
                    // about 16dp between lines, so no extra run spacing.
                    spacing: 12,
                    runSpacing: 0,
                    children: [
                      for (final c in chips)
                        ChoiceChip(
                          key: ValueKey('category-${c.id}'),
                          // The icon says "selected" with colour; a checkmark
                          // would draw on top of it.
                          showCheckmark: false,
                          avatar: Icon(
                            categoryIconFor(c.icon).icon,
                            size: 18,
                            color: c.id == selected
                                ? context.appColors.accent
                                : context.appColors.text,
                          ),
                          label: Text(
                            c.isArchived ? '${c.name} (archived)' : c.name,
                          ),
                          selected: c.id == selected,
                          onSelected: (_) => setState(() {
                            _categoryId = c.id;
                            _categoryError = null;
                          }),
                        ),
                      ActionChip(
                        key: const ValueKey('new-category'),
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('New'),
                        onPressed: _addCategory,
                      ),
                    ],
                  ),
                  if (_categoryError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _categoryError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('note-field'),
                    controller: _note,
                    maxLength: maxNoteLength,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('save-button'),
                    onPressed: _saving ? null : () => _save(active),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
