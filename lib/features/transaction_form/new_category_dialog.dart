import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/database_providers.dart';
import '../shared/icon_picker.dart';

/// Asks for a category's name and icon. With [existing] it edits that
/// category, otherwise it creates a new one of [type]. Returns the saved
/// category, or null if the user cancelled.
Future<CategoryRow?> showCategoryNameDialog(
  BuildContext context, {
  required TransactionType type,
  CategoryRow? existing,
}) {
  return showDialog<CategoryRow>(
    context: context,
    builder: (_) => _CategoryDialog(type: type, existing: existing),
  );
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({required this.type, this.existing});

  final TransactionType type;
  final CategoryRow? existing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String _icon = widget.existing?.icon ?? defaultCategoryIconKey;
  String? _error;

  /// Set when the typed name matches an archived category.
  CategoryRow? _archivedMatch;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repo = ref.read(categoryRepositoryProvider);
    final name = _controller.text;
    try {
      final existing = widget.existing;
      final CategoryRow saved;
      if (existing == null) {
        saved = await repo.add(name, widget.type, icon: _icon);
      } else {
        await repo.update(existing.id, name: name, icon: _icon);
        saved = (await repo.getById(existing.id))!;
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on InvalidCategoryNameException {
      setState(() {
        _error = 'Enter a name';
        _archivedMatch = null;
      });
    } on DuplicateCategoryException catch (e) {
      setState(() {
        _archivedMatch = e.archivedMatch;
        _error = e.archivedMatch != null
            ? '"${e.archivedMatch!.name}" is archived'
            : 'A category named "${e.name.trim()}" already exists';
      });
    } on ProtectedCategoryException {
      setState(() => _error = '"Other" keeps its name');
    }
  }

  Future<void> _restoreArchived() async {
    final match = _archivedMatch!;
    final repo = ref.read(categoryRepositoryProvider);
    await repo.restore(match.id);
    final restored = await repo.getById(match.id);
    if (mounted) Navigator.of(context).pop(restored);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final editing = existing != null;
    final protected = existing?.isProtected ?? false;
    return AlertDialog(
      title: Text(editing ? 'Edit category' : 'New category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('category-name-field'),
              controller: _controller,
              autofocus: !protected,
              enabled: !protected,
              maxLength: categoryNameFieldLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                helperText: protected ? '"Other" keeps its name' : null,
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() {
                    _error = null;
                    _archivedMatch = null;
                  });
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            IconPicker(
              selectedKey: _icon,
              onChanged: (key) => setState(() => _icon = key),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_archivedMatch != null)
          TextButton(onPressed: _restoreArchived, child: const Text('Restore')),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }
}
