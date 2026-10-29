import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/trends.dart';
import '../../providers/trends_providers.dart';

/// The 3 / 6 / 12 month choice shared by the Insights tab and the Trends page.
/// Each chip's key is `<keyPrefix>-<months>`.
class TrendWindowChips extends ConsumerWidget {
  const TrendWindowChips({super.key, required this.keyPrefix});

  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(trendWindowProvider);
    return Wrap(
      spacing: Gap.m,
      children: [
        for (final n in trendWindows)
          ChoiceChip(
            key: ValueKey('$keyPrefix-$n'),
            showCheckmark: false,
            label: Text('$n months'),
            selected: window == n,
            onSelected: (_) => ref.read(trendWindowProvider.notifier).set(n),
          ),
      ],
    );
  }
}
