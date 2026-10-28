import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup/backup_data.dart';
import '../../domain/iso_date.dart';
import '../../providers/backup_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';

String _backupFileName(WidgetRef ref) =>
    'heisenbudget-backup-${toIsoDate(ref.read(clockProvider))}.json';

/// Hands a backup file to the phone's share sheet, where the person chooses
/// where it goes. Remembers the time (on this phone only) for the "Last
/// backup file" line and the backup reminder. [origin] is where the sheet
/// points from (an iPad needs it).
Future<void> shareBackup(WidgetRef ref, {Rect? origin}) async {
  final data = await ref
      .read(backupServiceProvider)
      .snapshot(now: ref.read(nowProvider)());
  await ref
      .read(fileExchangeProvider)
      .shareFile(
        fileName: _backupFileName(ref),
        mimeType: 'application/json',
        bytes: await data.toBytes(),
        origin: origin,
      );
  await ref
      .read(settingsProvider.notifier)
      .setLastBackupAt(ref.read(nowProvider)());
}

/// Saves a backup file where the person points the phone's save dialog (any
/// folder they choose). True when it was saved; false, and nothing recorded,
/// when they closed the dialog.
Future<bool> saveBackupToFolder(WidgetRef ref) async {
  final data = await ref
      .read(backupServiceProvider)
      .snapshot(now: ref.read(nowProvider)());
  final saved = await ref
      .read(fileExchangeProvider)
      .saveFile(
        fileName: _backupFileName(ref),
        mimeType: 'application/json',
        bytes: await data.toBytes(),
      );
  if (!saved) return false;
  await ref
      .read(settingsProvider.notifier)
      .setLastBackupAt(ref.read(nowProvider)());
  return true;
}

/// "Back up now" from a card on Home or the report: opens the share sheet from
/// the widget at [context], and says in a snack bar when it could not.
Future<void> backUpNow(BuildContext context, WidgetRef ref) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await shareBackup(ref, origin: origin);
  } on BackupFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Something went wrong. No backup was made.'),
      ),
    );
  }
}
