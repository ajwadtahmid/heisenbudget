import 'package:flutter/material.dart';

import '../../core/category_icons.dart';
import '../../core/theme.dart';

/// Choose a category icon: a search box above sections of icons. The grid
/// scrolls on its own (so the dialog stays a sensible size) and opens scrolled
/// to the icon that is already selected.
class IconPicker extends StatefulWidget {
  const IconPicker({
    super.key,
    required this.selectedKey,
    required this.onChanged,
    this.height = 260,
  });

  final String selectedKey;
  final ValueChanged<String> onChanged;

  /// Height of the scrolling grid under the search box.
  final double height;

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  final _searchController = TextEditingController();
  final _selectedItemKey = GlobalKey();
  final _selectedGroupKey = GlobalKey();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Bring the current icon into view once the grid has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Open on the selected icon's section, heading first, so no icons
      // show without their heading.
      final target =
          _selectedGroupKey.currentContext ?? _selectedItemKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: 0);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = categoryIconFor(widget.selectedKey).key;
    final matches = searchCategoryIcons(_query);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('icon-search'),
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search icons',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    'No icons match "${_query.trim()}"',
                    key: const ValueKey('icon-no-results'),
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in categoryIconGroups)
                        ..._section(theme, group, [
                          for (final o in matches)
                            if (o.group == group) o,
                        ], selected),
                      // Room after the last section so any heading can scroll to the top.
                      SizedBox(height: widget.height - 56),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  List<Widget> _section(
    ThemeData theme,
    String group,
    List<CategoryIconOption> options,
    String selected,
  ) {
    if (options.isEmpty) return const [];
    return [
      Padding(
        key: options.any((o) => o.key == selected) ? _selectedGroupKey : null,
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          group,
          key: ValueKey('icon-group-$group'),
          style: theme.textTheme.labelMedium,
        ),
      ),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final option in options)
            _IconChoice(
              // The global key lets the picker scroll the chosen icon into view.
              key: option.key == selected
                  ? _selectedItemKey
                  : ValueKey('item-${option.key}'),
              testKey: ValueKey('icon-${option.key}'),
              option: option,
              selected: option.key == selected,
              onTap: () => widget.onChanged(option.key),
            ),
        ],
      ),
    ];
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    super.key,
    required this.testKey,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  /// `icon-<key>`: the same for every icon, whether or not it is selected.
  final Key testKey;
  final CategoryIconOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: testKey,
      child: IconButton(
        tooltip: option.label,
        isSelected: selected,
        icon: Icon(option.icon),
        selectedIcon: Icon(option.icon),
        // Square, like every other selectable thing in the app.
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          backgroundColor: selected ? scheme.primaryContainer : null,
          foregroundColor: selected ? scheme.onPrimaryContainer : null,
        ),
        onPressed: onTap,
      ),
    );
  }
}
