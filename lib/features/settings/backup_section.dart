import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/backup/backup_data.dart';
import '../../data/backup/csv_export.dart';
import '../../domain/iso_date.dart';
import '../../providers/backup_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
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
    return Column(
      children: [
        ListTile(
          key: const ValueKey('export-backup'),
          contentPadding: EdgeInsets.zero,
          enabled: !_busy,
          leading: const Icon(Icons.ios_share_outlined),
          title: const Text('Back up'),
          subtitle: const Text('Save everything to a file you can keep.'),
          onTap: () => _run(_exportBackup),
        ),
        ListTile(
          key: const ValueKey('restore-backup'),
          contentPadding: EdgeInsets.zero,
          enabled: !_busy,
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('Restore from backup'),
          subtitle: const Text('Replace everything here with a backup file.'),
          onTap: () => _run(_restore),
        ),
        ListTile(
          key: const ValueKey('export-csv'),
          contentPadding: EdgeInsets.zero,
          enabled: !_busy,
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Export to CSV'),
          subtitle: const Text('All transactions, for a spreadsheet.'),
          onTap: () => _run(_exportCsv),
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
          bytes: Uint8List.fromList(utf8.encode(data.encode())),
          origin: origin,
        );
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
    final data = BackupData.parse(bytes);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmRestoreDialog(data: data),
    );
    if (ok != true) return;
    await ref.read(backupServiceProvider).restore(data);
    // Screens that show data update by themselves; these two held old state.
    ref.invalidate(settingsProvider);
    ref.invalidate(historyFilterProvider);
    _say('Backup restored.');
  }
}

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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
