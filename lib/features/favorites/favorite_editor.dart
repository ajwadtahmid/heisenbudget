import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/favorite_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/favorite_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../transaction_form/transaction_draft.dart';

/// Opens the favorite editor. Give [from] to save a transaction's values as a
/// new favorite, or [existing] to change one.
Future<void> showFavoriteEditor(
  BuildContext context, {
  FavoriteRow? existing,
  TransactionDraft? from,
}) {
  assert(existing != null || from != null);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FavoriteEditor(existing: existing, from: from),
  );
}

class _FavoriteEditor extends ConsumerStatefulWidget {
  const _FavoriteEditor({this.existing, this.from});

  final FavoriteRow? existing;
  final TransactionDraft? from;

  @override
  ConsumerState<_FavoriteEditor> createState() => _FavoriteEditorState();
}

class _FavoriteEditorState extends ConsumerState<_FavoriteEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TransactionType _type;
  int? _categoryId;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final from = widget.from;
    _type = existing?.type ?? from!.type;
    _categoryId = existing?.categoryId ?? from?.categoryId;
    final cents = existing != null ? existing.amountCents : from?.amountCents;
    _amount = TextEditingController(
      text: cents == null ? '' : centsToInputText(cents),
    );
    final note = existing?.note ?? from?.note ?? '';
    _note = TextEditingController(text: note);
    _label = TextEditingController(
      text: existing?.label ?? _suggestLabel(note),
    );
  }

  /// A short name to start from: the note, else filled in once categories load.
  String _suggestLabel(String note) {
    final firstLine = note.trim().split('\n').first.trim();
    return firstLine.length <= maxFavoriteLabelLength
        ? firstLine
        : firstLine.substring(0, maxFavoriteLabelLength).trimRight();
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The selected category, else the usual default for this type.
  int? _selected(List<CategoryRow> active) {
    final picked = _categoryId;
    if (picked != null) return picked;
    for (final c in active) {
      if (c.isProtected) return c.id;
    }
    return active.isEmpty ? null : active.first.id;
  }

  Future<void> _save(List<CategoryRow> active, List<CategoryRow> all) async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final categoryId = _selected(active);
    if (categoryId == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    // A blank label falls back to the category's name.
    final category = all.where((c) => c.id == categoryId).firstOrNull;
    final label = _label.text.trim().isEmpty
        ? (category?.name ?? 'Favorite')
        : _label.text.trim();
    final text = _amount.text.trim();
    final input = FavoriteInput(
      label: label.length > maxFavoriteLabelLength
          ? label.substring(0, maxFavoriteLabelLength)
          : label,
      type: _type,
      categoryId: categoryId,
      amountCents: text.isEmpty ? null : parseMoney(text).cents,
      note: _note.text,
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(favoriteRepositoryProvider);
    final messenger = ref.read(rootMessengerKeyProvider);
    try {
      if (_isNew) {
        await repo.add(input);
      } else {
        await repo.update(widget.existing!.id, input);
      }
    } on FavoriteLimitException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'You can have up to $maxFavorites favorites. Delete one in '
              'Settings first.';
        });
      }
      return;
    }
    if (_isNew) {
      messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Saved “${input.label}” to Quick add.')),
        );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final active = ref.watch(activeCategoriesProvider(_type)).value ?? const [];
    final all = ref.watch(allCategoriesProvider).value ?? const [];
    final selected = _selected(active);
    final chips = [...active];
    if (selected != null && !chips.any((x) => x.id == selected)) {
      chips.addAll(all.where((x) => x.id == selected && x.type == _type));
    }

    return Padding(
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
                    _isNew ? 'Save as favorite' : 'Edit favorite',
                    style: theme.textTheme.titleLarge,
                  ),
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
                  Text(
                    _type == TransactionType.income ? 'Income' : 'Expense',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: Gap.m),
                  TextFormField(
                    key: const ValueKey('favorite-label'),
                    controller: _label,
                    maxLength: maxFavoriteLabelLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      helperText: 'Shown on the Quick add button',
                    ),
                  ),
                  const SizedBox(height: Gap.m),
                  ClampedTextScale(
                    child: TextFormField(
                      key: const ValueKey('favorite-amount'),
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                      ],
                      style: monoText(
                        size: 28,
                        weight: FontWeight.w600,
                        color: c.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount (optional)',
                        helperText: 'Leave empty to enter it each time',
                        prefixText: '$symbol ',
                        prefixStyle: monoText(
                          size: 28,
                          weight: FontWeight.w500,
                          color: c.dim,
                        ),
                      ),
                      // Empty is fine (a variable amount); anything typed
                      // must be a real amount.
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? null
                          : parseMoney(v).error,
                    ),
                  ),
                  const SizedBox(height: Gap.l),
                  Text('Category', style: theme.textTheme.labelLarge),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: 12,
                    runSpacing: 0,
                    children: [
                      for (final cat in chips)
                        ChoiceChip(
                          key: ValueKey('favorite-category-${cat.id}'),
                          showCheckmark: false,
                          avatar: Icon(
                            categoryIconFor(cat.icon).icon,
                            size: 18,
                            color: cat.id == selected ? c.accent : c.text,
                          ),
                          label: Text(
                            cat.isArchived
                                ? '${cat.name} (archived)'
                                : cat.name,
                          ),
                          selected: cat.id == selected,
                          onSelected: (_) => setState(() {
                            _categoryId = cat.id;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.l),
                  TextFormField(
                    key: const ValueKey('favorite-note'),
                    controller: _note,
                    maxLength: maxNoteLength,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.s),
                      child: Text(
                        _error!,
                        key: const ValueKey('favorite-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: Gap.s),
                  FilledButton(
                    key: const ValueKey('favorite-save'),
                    onPressed: _saving ? null : () => _save(active, all),
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
