import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/backup/backup_data.dart';
import '../../data/database/database_opener.dart';

/// Shown instead of the app when its data cannot be opened (a failed update,
/// a damaged file, or a file from a newer version). Nothing is deleted unless
/// the person chooses it, and each way out says what it does.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({
    super.key,
    required this.error,
    required this.copyMadeAt,
    required this.pickBackup,
    required this.onRetry,
    required this.onRestoreCopy,
    required this.onRestoreBackup,
    required this.onErase,
  });

  final DatabaseOpenException error;

  /// When the copy made before the last update was taken; null when there is none.
  final DateTime? copyMadeAt;

  /// Lets the person choose a backup file (null if they cancel).
  final Future<Uint8List?> Function() pickBackup;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRestoreCopy;
  final Future<void> Function(BackupData data) onRestoreBackup;
  final Future<void> Function() onErase;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BackupFormatException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      debugPrint('Recovery action failed: $e');
      if (mounted) {
        setState(
          () =>
              _message = 'That did not work. Try again, or choose another way.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const ValueKey('recovery-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('recovery-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restoreCopy() async {
    final made = widget.copyMadeAt;
    final ok = await _confirm(
      title: 'Go back to the copy?',
      body:
          'This puts back the copy of your data made before the last update'
          '${made == null ? '' : ' (${formatDate(made.toLocal())})'}. '
          'Anything added since then is lost.',
      action: 'Restore the copy',
    );
    if (ok) await _run(widget.onRestoreCopy);
  }

  Future<void> _restoreBackup() async {
    await _run(() async {
      final bytes = await widget.pickBackup();
      if (bytes == null) return;
      final data = await BackupData.parseInBackground(bytes);
      final n = data.transactions.length;
      final ok = await _confirm(
        title: 'Restore this backup?',
        body:
            'It has $n transaction${n == 1 ? '' : 's'} and replaces what is '
            'on this phone now. This cannot be undone.',
        action: 'Restore',
      );
      if (ok) await widget.onRestoreBackup(data);
    });
  }

  Future<void> _erase() async {
    final ok = await _confirm(
      title: 'Erase everything?',
      body:
          'This deletes all data on this phone, including any safety copy, '
          'and starts the app over. It cannot be undone.',
      action: 'Erase everything',
      destructive: true,
    );
    if (ok) await _run(widget.onErase);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final made = widget.copyMadeAt;
    final cause = widget.error.cause.toString();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(Icons.error_outline, size: 40, color: c.error),
                const SizedBox(height: Gap.m),
                Text(
                  'Heisenbudget could not open your data',
                  key: const ValueKey('recovery-title'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: Gap.s),
                Text(
                  'Nothing has been deleted. Choose how to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
                ),
                const SizedBox(height: Gap.l),
                FilledButton(
                  key: const ValueKey('recovery-retry'),
                  onPressed: _busy ? null : () => _run(widget.onRetry),
                  child: const Text('Try again'),
                ),
                if (made != null) ...[
                  const SizedBox(height: Gap.s),
                  OutlinedButton(
                    key: const ValueKey('recovery-restore-copy'),
                    onPressed: _busy ? null : _restoreCopy,
                    child: Text(
                      'Restore the copy from before the update '
                      '(${formatDate(made.toLocal())})',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.s),
                OutlinedButton(
                  key: const ValueKey('recovery-restore-backup'),
                  onPressed: _busy ? null : _restoreBackup,
                  child: const Text(
                    'Restore from a backup file',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: Gap.s),
                TextButton(
                  key: const ValueKey('recovery-erase'),
                  style: TextButton.styleFrom(foregroundColor: c.error),
                  onPressed: _busy ? null : _erase,
                  child: const Text(
                    'Erase everything and start over',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: Gap.m),
                  Text(
                    _message!,
                    key: const ValueKey('recovery-message'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.error),
                  ),
                ],
                const SizedBox(height: Gap.l),
                ExpansionTile(
                  key: const ValueKey('recovery-details'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Details'),
                  children: [
                    SelectableText(
                      cause.length > 300
                          ? '${cause.substring(0, 300)}...'
                          : cause,
                      style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
