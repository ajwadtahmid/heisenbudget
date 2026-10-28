import 'package:flutter/material.dart';

import '../../core/design/section_label.dart';
import '../../core/theme.dart';

/// A short look at something that has a page of its own (Trends, Goals): a
/// section label with "See all" at the end, then [child]. Tapping "See all"
/// opens the page; the glance itself stays small.
class HomeGlance extends StatelessWidget {
  const HomeGlance({
    super.key,
    required this.label,
    required this.child,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });

  final String label;
  final Widget child;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          label,
          trailing: onSeeAll == null
              ? null
              : TextButton(
                  key: const ValueKey('glance-see-all'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                  onPressed: onSeeAll,
                  child: Text(seeAllLabel),
                ),
        ),
        const SizedBox(height: Gap.m),
        child,
      ],
    );
  }
}
