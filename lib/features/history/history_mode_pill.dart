import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/budget_history_providers.dart';

/// The Transactions | Budgets switch at the top of History: a rounded track
/// with the chosen side filled in the accent.
class HistoryModePill extends ConsumerWidget {
  const HistoryModePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(historyModeProvider);
    final c = context.appColors;

    Widget segment(HistoryMode value, String label) {
      final selected = mode == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: ExcludeSemantics(
            child: Material(
              color: selected ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                key: ValueKey('history-mode-${value.name}'),
                borderRadius: BorderRadius.circular(24),
                onTap: () => ref.read(historyModeProvider.notifier).set(value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? c.onAccent : c.dim,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              children: [
                segment(HistoryMode.transactions, 'Transactions'),
                segment(HistoryMode.budgets, 'Budgets'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
