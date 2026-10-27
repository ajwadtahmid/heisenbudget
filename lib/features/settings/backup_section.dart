import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/backup/backup_data.dart';
import '../../data/backup/csv_export.dart';
import '../../domain/iso_date.dart';
import '../../domain/backup_status.dart';
import '../../providers/backup_providers.dart';
import '../../providers/budget_history_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/recurring_catch_up.dart';
import 'settings_widgets.dart';
import '../../providers/database_providers.dart';

/// Back up, restore and export, all through the phone's own share sheet and
/// file picker. Nothing leaves the phone unless the user sends it.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(settingsProvider.select((s) => s.lastBackupAt));
    final today = ref.watch(clockProvider);
    final freshness = backupFreshness(last, today);
    final status = switch (freshness) {
      BackupFreshness.never => 'Not backed up yet',
      BackupFreshness.recent =>
        'Last backup file: ${formatDate(last!.toLocal())}',
      BackupFreshness.stale =>
        'Last backup file: ${formatDate(last!.toLocal())} · '
            '${daysSinceBackup(last, today)} days ago',
    };
    return Column(
      children: [
        SettingsRow(
          key: const ValueKey('export-backup'),
          icon: Icons.ios_share_outlined,
          title: 'Back up',
          summary: status,
          emphasizeSummary: freshness == BackupFreshness.stale,
          enabled: !_busy,
          onTap: () => _run(_exportBackup),
        ),
        SettingsRow(
          key: const ValueKey('restore-backup'),
          icon: Icons.settings_backup_restore,
          title: 'Restore from backup',
          summary: 'Replace everything here with a backup file.',
          enabled: !_busy,
          onTap: () => _run(_restore),
        ),
        SettingsRow(
          key: const ValueKey('export-csv'),
          icon: Icons.table_chart_outlined,
          title: 'Export to CSV',
          summary: 'All transactions, for a spreadsheet.',
          enabled: !_busy,
          onTap: () => _run(_exportCsv),
        ),
        SettingsRow(
          key: const ValueKey('erase-everything'),
          icon: Icons.delete_forever_outlined,
          title: 'Erase everything',
          summary: 'Delete all data on this phone and start over.',
          destructive: true,
          enabled: !_busy,
          onTap: () => _run(_erase),
        ),
      ],
    );
  }

  /// Runs one action with the tiles disabled, and turns any unexpected
  /// failure into a short message instead of a crash.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on BackupFormatException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Something went wrong. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Where the share sheet should point from (iPad needs it).
  Rect? _origin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  String get _today => toIsoDate(ref.read(clockProvider));

  Future<void> _exportBackup() async {
    final origin = _origin();
    final data = await ref
        .read(backupServiceProvider)
        .snapshot(now: ref.read(nowProvider)());
    await ref
        .read(fileExchangeProvider)
        .shareFile(
          fileName: 'heisenbudget-backup-$_today.json',
          mimeType: 'application/json',
          bytes: await data.toBytes(),
          origin: origin,
        );
    // Remembered for the "Last backup file" line (on this phone only).
    await ref
        .read(settingsProvider.notifier)
        .setLastBackupAt(ref.read(nowProvider)());
  }

  Future<void> _exportCsv() async {
    final origin = _origin();
    final rows = await ref.read(transactionRepositoryProvider).getAll();
    if (rows.isEmpty) {
      _say('No transactions to export yet.');
      return;
    }
    await ref
        .read(fileExchangeProvider)
        .shareFile(
          fileName: 'heisenbudget-transactions-$_today.csv',
          mimeType: 'text/csv',
          bytes: Uint8List.fromList(utf8.encode(buildTransactionsCsv(rows))),
          origin: origin,
        );
  }

  Future<void> _restore() async {
    final bytes = await ref.read(fileExchangeProvider).pickFile();
    if (bytes == null) return;
    final data = await BackupData.parseInBackground(bytes);
    // The dialog offers a backup of what is here now first; after it, the
    // question is asked again.
    while (true) {
      if (!mounted) return;
      final choice = await showDialog<_RestoreChoice>(
        context: context,
        builder: (_) => _ConfirmRestoreDialog(data: data),
      );
      if (choice == _RestoreChoice.backupFirst) {
        await _exportBackup();
        continue;
      }
      if (choice != _RestoreChoice.restore) return;
      break;
    }
    try {
      await ref.read(backupServiceProvider).restore(data);
    } finally {
      // Even when only the settings step failed the data was replaced, so
      // whatever held old state starts fresh either way. Screens that show
      // data update by themselves; filters hold ids that may no longer exist.
      _forgetOldState();
    }
    _say('Backup restored.');
    // Repeating transactions that fell due since the backup was made.
    await runRecurringCatchUp(ref);
  }

  /// Two steps, then everything is wiped and the app starts over.
  Future<void> _erase() async {
    final first = await showDialog<_EraseChoice>(
      context: context,
      builder: (_) => const _EraseWarningDialog(),
    );
    if (first == null || first == _EraseChoice.cancel || !mounted) return;
    if (first == _EraseChoice.backupFirst) {
      await _exportBackup();
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => const _EraseConfirmDialog(),
    );
    if (sure != true) return;

    await ref.read(backupServiceProvider).eraseEverything();
    await ref.read(fileExchangeProvider).clearTemporaryFiles();
    // Everything that held old state starts fresh; the welcome tour returns.
    _forgetOldState();
    ref.invalidate(selectedPeriodProvider);
    ref.invalidate(shellTabProvider);
    ref.invalidate(needsWelcomeProvider);
  }

  /// State that points at data a restore or an erase just replaced.
  void _forgetOldState() {
    ref.invalidate(settingsProvider);
    ref.invalidate(historyFilterProvider);
    ref.invalidate(historyModeProvider);
    ref.invalidate(budgetHistoryFilterProvider);
    ref.invalidate(budgetHistoryCountProvider);
  }
}

enum _RestoreChoice { cancel, backupFirst, restore }

class _ConfirmRestoreDialog extends StatelessWidget {
  const _ConfirmRestoreDialog({required this.data});

  final BackupData data;

  @override
  Widget build(BuildContext context) {
    final n = data.transactions.length;
    final k = data.categories.length;
    final made = data.exportedAt.millisecondsSinceEpoch == 0
        ? null
        : formatDate(data.exportedAt.toLocal());
    return AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        '${made == null ? 'This backup' : 'Backup from $made'} has '
        '$n transaction${n == 1 ? '' : 's'} and '
        '$k categor${k == 1 ? 'y' : 'ies'}.\n\n'
        'It replaces everything on this phone: transactions, categories and '
        'settings. This cannot be undone.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore-cancel'),
          onPressed: () => Navigator.of(context).pop(_RestoreChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('restore-backup-first'),
          onPressed: () =>
              Navigator.of(context).pop(_RestoreChoice.backupFirst),
          child: const Text('Back up current data first'),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm'),
          onPressed: () => Navigator.of(context).pop(_RestoreChoice.restore),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

enum _EraseChoice { cancel, backupFirst, continueOn }

/// Step one: say what will happen and offer a backup first.
class _EraseWarningDialog extends StatelessWidget {
  const _EraseWarningDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Erase everything?'),
      content: const Text(
        'This deletes every transaction, category, repeating transaction, '
        'favorite and setting on this phone, then starts the app over. It '
        'cannot be undone.\n\nBack up first if you might want any of it '
        'back.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('erase-cancel'),
          onPressed: () => Navigator.of(context).pop(_EraseChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('erase-backup-first'),
          onPressed: () => Navigator.of(context).pop(_EraseChoice.backupFirst),
          child: const Text('Back up first'),
        ),
        TextButton(
          key: const ValueKey('erase-continue'),
          onPressed: () => Navigator.of(context).pop(_EraseChoice.continueOn),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// Step two: the last chance.
class _EraseConfirmDialog extends StatelessWidget {
  const _EraseConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Erase everything now?'),
      content: const Text('Everything on this phone will be deleted.'),
      actions: [
        TextButton(
          key: const ValueKey('erase-keep'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my data'),
        ),
        FilledButton(
          key: const ValueKey('erase-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Erase everything'),
        ),
      ],
    );
  }
}
