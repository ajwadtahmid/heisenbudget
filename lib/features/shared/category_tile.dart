import 'package:flutter/material.dart';

import '../../core/category_icons.dart';
import '../../core/theme.dart';

/// A small outlined square holding a category's icon.
/// Decorative only: the category name is always shown next to it.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.iconKey,
    this.size = 36,
    this.archived = false,
  });

  /// A key from `categoryIcons`; unknown keys show the general icon.
  final String iconKey;
  final double size;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: archived ? c.hairline : c.faint),
        ),
        child: Icon(
          categoryIconFor(iconKey).icon,
          size: size * 0.55,
          color: archived ? c.faint : c.text,
        ),
      ),
    );
  }
}
