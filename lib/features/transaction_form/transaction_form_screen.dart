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
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/quick_add_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../data/repositories/recurring_repository.dart';
import '../settings/recurring_editor_screen.dart';
import '../shared/recurring_catch_up.dart';
import '../../providers/favorite_providers.dart';
import '../favorites/favorite_chip.dart';
import '../favorites/favorite_editor.dart';
import '../favorites/quick_log.dart';
import 'new_category_dialog.dart';
import 'transaction_draft.dart';
import 'repeat_sheet.dart';

/// Opens the Add form, or the Edit form when [editId] is given. A [draft]
/// starts the Add form with those values filled in.
Future<void> showTransactionForm(
  BuildContext context, {
  int? editId,
  TransactionDraft? draft,
}) async {
  final duplicate = await showModalBottomSheet<TransactionDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TransactionFormSheet(editId: editId, draft: draft),
  );
  // "Duplicate" closes the Edit sheet and opens a new one with its values.
  if (duplicate != null && context.mounted) {
    await showTransactionForm(context, draft: duplicate);
  }
}

/// The content of the add/edit bottom sheet.
class TransactionFormSheet extends ConsumerWidget {
  const TransactionFormSheet({super.key, this.editId, this.draft});

  final int? editId;
  final TransactionDraft? draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = editId;
    if (id == null) return _TransactionForm(draft: draft);

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
  const _TransactionForm({this.existing, this.draft});

  final TransactionWithCategory? existing;
  final TransactionDraft? draft;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _title;
  final _amountFocus = FocusNode();
  late TransactionType _type;
  late DateTime _date;

  /// null = nothing picked yet; the default (last used, else "Other") applies.
  int? _categoryId;
  String? _categoryError;
  bool _saving = false;

  /// How this new (or not yet repeating) transaction repeats; null = once.
  RepeatChoice? _repeat;

  bool get _isEdit => widget.existing != null;

  late final AddSheetCount _openSheets;

  @override
  void initState() {
    super.initState();
    // Counted so a launcher shortcut does not open a second sheet on top of
    // this one. The updates wait a moment: a provider must not change while
    // the widget tree is being built.
    _openSheets = ref.read(addSheetCountProvider.notifier);
    Future.microtask(_openSheets.opened);
    final tx = widget.existing?.transaction;
    final draft = widget.draft;
    _type = tx?.type ?? draft?.type ?? TransactionType.expense;
    _date = tx != null ? fromIsoDate(tx.date) : ref.read(clockProvider);
    _categoryId = tx?.categoryId ?? draft?.categoryId;
    final cents = tx?.amountCents ?? draft?.amountCents;
    _amount = TextEditingController(
      text: cents != null ? centsToInputText(cents) : '',
    );
    _note = TextEditingController(text: tx?.note ?? draft?.note ?? '');
    _title = TextEditingController(text: tx?.title ?? draft?.title ?? '');
  }

  @override
  void dispose() {
    Future.microtask(_openSheets.closed);
    _amount.dispose();
    _note.dispose();
    _title.dispose();
    _amountFocus.dispose();
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

  /// Whether the Repeat row is offered: new transactions and ones that do not
  /// repeat yet. One made by a rule shows the rule instead.
  bool get _canSetRepeat =>
      !_isEdit || widget.existing!.transaction.recurringRuleId == null;

  Recurrence? _recurrence(RepeatChoice? r) => r == null
      ? null
      : Recurrence(
          unit: r.unit,
          interval: r.interval,
          start: _date,
          end: r.end,
        );

  /// Earlier occurrences that saving with this repeat adds up to today.
  int _earlierCount(RepeatChoice r) {
    final today = ref.read(clockProvider);
    return _recurrence(r)!
        .dueThrough(today, fromIndex: 1, limit: maxCatchUpPerRule + 1)
        .length;
  }

  /// A reason the repeat cannot be saved, or null.
  String? _repeatError(RepeatChoice? r) {
    if (r == null) return null;
    final end = r.end;
    if (end != null && end.isBefore(dateOnly(_date))) {
      return 'The end date is before this transaction\'s date.';
    }
    if (_earlierCount(r) > maxCatchUpPerRule) {
      return 'That would add more than $maxCatchUpPerRule earlier '
          'transactions. Choose a later date.';
    }
    return null;
  }

  Future<void> _pickRepeat() async {
    final result = await showRepeatSheet(
      context,
      start: _date,
      current: _repeat,
    );
    if (result != null && mounted) setState(() => _repeat = result.choice);
  }

  Future<void> _save(List<CategoryRow> active) async {
    if (_saving) return;
    final categoryId = _selectedCategory(active);
    setState(
      () => _categoryError = categoryId == null ? 'Pick a category' : null,
    );
    if (!_formKey.currentState!.validate() || categoryId == null) return;
    if (_canSetRepeat && _repeatError(_repeat) != null) {
      setState(() {});
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(transactionRepositoryProvider);
    final input = TransactionInput(
      amountCents: parseMoney(_amount.text).cents!,
      type: _type,
      date: _date,
      categoryId: categoryId,
      note: _note.text,
      title: _title.text,
    );
    final existing = widget.existing;
    final repeat = _canSetRepeat ? _repeat : null;
    final rules = ref.read(recurringRepositoryProvider);
    if (existing == null) {
      if (repeat == null) {
        await repo.add(input);
      } else {
        await rules.addWithRule(
          input,
          RecurringInput(
            amountCents: input.amountCents,
            type: _type,
            categoryId: categoryId,
            note: _note.text,
            title: _title.text,
            unit: repeat.unit,
            interval: repeat.interval,
            start: _date,
            end: repeat.end,
          ),
        );
      }
    } else {
      final tx = existing.transaction;
      // Moving a rule's transaction to another day takes it out of the rule.
      final unlink = tx.recurringRuleId != null && tx.date != toIsoDate(_date);
      await repo.update(tx.id, input, unlinkRule: unlink);
      if (repeat != null) {
        await rules.makeRecurring(
          tx.id,
          unit: repeat.unit,
          interval: repeat.interval,
          end: repeat.end,
        );
      }
    }
    await ref
        .read(settingsProvider.notifier)
        .setLastCategory(_type, categoryId);
    HapticFeedback.lightImpact();
    // A rule that starts in the past fills in the days since.
    if (repeat != null) await runRecurringCatchUp(ref);
    if (mounted) Navigator.of(context).pop();
  }

  /// The Quick add row shows when adding a plain new transaction: not when
  /// editing, and not when the sheet was opened already filled in.
  bool get _showQuickAdd => !_isEdit && widget.draft == null;

  /// What tapping a favorite does: log it right away and close the sheet,
  /// or, when it cannot be logged as it is (no amount, or its category was
  /// archived) or an amount is already typed, fill the form with it.
  Future<void> _onFavoriteTap(
    FavoriteRow favorite,
    List<CategoryRow> categories,
  ) async {
    final typing = _amount.text.trim().isNotEmpty;
    if (typing || !canLogDirectly(favorite, categories)) {
      _fillFrom(favorite, categories);
      return;
    }
    await logFavoriteNow(ref, favorite);
    if (mounted) Navigator.of(context).pop();
  }

  /// Puts a favorite's values in the form, ready to change before saving.
  void _fillFrom(FavoriteRow favorite, List<CategoryRow> categories) {
    final category = categories.where((c) => c.id == favorite.categoryId);
    final usable = category.isNotEmpty && !category.first.isArchived;
    final cents = favorite.amountCents;
    setState(() {
      _type = favorite.type;
      _categoryId = usable ? favorite.categoryId : null;
      _categoryError = null;
      _amount.text = cents == null ? '' : centsToInputText(cents);
      _title.text = favorite.title ?? '';
      _note.text = favorite.note ?? '';
    });
    _amountFocus.requestFocus();
  }

  Widget _quickAddRow(BuildContext context, List<CategoryRow> categories) {
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    if (!_showQuickAdd || favorites.isEmpty) return const SizedBox.shrink();
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick add', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          key: const ValueKey('quick-add-row'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final favorite in favorites)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FavoriteChip(
                    key: ValueKey('favorite-${favorite.id}'),
                    favorite: favorite,
                    iconKey: categories
                        .where((c) => c.id == favorite.categoryId)
                        .map((c) => c.icon)
                        .firstOrNull,
                    symbol: symbol,
                    onTap: () => _onFavoriteTap(favorite, categories),
                    onLongPress: () => _fillFrom(favorite, categories),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _onAction(_FormAction action) {
    final existing = widget.existing!;
    final draft = TransactionDraft.fromTransaction(existing);
    switch (action) {
      case _FormAction.duplicate:
        Navigator.of(context).pop(draft);
      case _FormAction.favorite:
        showFavoriteEditor(context, from: draft);
    }
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

  List<Widget> _repeatRows(BuildContext context) {
    final r = _repeat;
    final c = context.appColors;
    final theme = Theme.of(context);
    final error = _repeatError(r);
    final earlier = r != null && error == null ? _earlierCount(r) : 0;
    final end = r?.end;
    final subtitle = r == null
        ? 'Does not repeat'
        : '${_recurrence(r)!.scheduleText}'
              '${end == null ? '' : ' · until ${formatDate(end)}'}';
    final note =
        error ??
        (earlier > 0
            ? 'Also adds $earlier earlier '
                  'transaction${earlier == 1 ? '' : 's'} up to today.'
            : null);
    return [
      ListTile(
        key: const ValueKey('repeat-tile'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.repeat),
        title: const Text('Repeat'),
        subtitle: Text(subtitle),
        onTap: _pickRepeat,
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            note,
            key: const ValueKey('repeat-note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: error != null ? c.error : c.dim,
            ),
          ),
        ),
    ];
  }

  /// A transaction made by a repeating rule: say so, and link to the rule.
  List<Widget> _linkedRuleRows(BuildContext context) {
    final tx = widget.existing!.transaction;
    final rules = ref.watch(recurringRulesProvider).value ?? const [];
    RecurringRuleRow? rule;
    for (final candidate in rules) {
      if (candidate.id == tx.recurringRuleId) rule = candidate;
    }
    if (rule == null) return const [];
    final found = rule;
    return [
      ListTile(
        key: const ValueKey('repeat-linked'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.repeat),
        title: const Text('Part of a repeating rule'),
        subtitle: Text(found.recurrence.scheduleText),
        trailing: TextButton(
          key: const ValueKey('edit-rule'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RecurringEditorScreen(ruleId: found.id),
            ),
          ),
          child: const Text('Edit rule'),
        ),
      ),
      if (tx.date != toIsoDate(_date))
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Changing the date takes this one out of the repeat.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.dim),
          ),
        ),
    ];
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
                  PopupMenuButton<_FormAction>(
                    key: const ValueKey('form-menu'),
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert),
                    onSelected: _onAction,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _FormAction.duplicate,
                        child: Text('Duplicate'),
                      ),
                      PopupMenuItem(
                        value: _FormAction.favorite,
                        child: Text('Save as favorite'),
                      ),
                    ],
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
                  _quickAddRow(context, all),
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
                      focusNode: _amountFocus,
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
                  TextFormField(
                    key: const ValueKey('title-field'),
                    controller: _title,
                    maxLength: maxTitleLength,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                      hintText: 'A shop or a name, such as In & Out',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const ValueKey('date-tile'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date'),
                    subtitle: Text(formatDate(_date)),
                    onTap: _pickDate,
                  ),

                  if (_canSetRepeat)
                    ..._repeatRows(context)
                  else
                    ..._linkedRuleRows(context),
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

/// Actions in the Edit sheet's header menu.
enum _FormAction { duplicate, favorite }
