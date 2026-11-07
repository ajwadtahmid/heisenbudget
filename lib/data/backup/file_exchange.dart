import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_data.dart';
import 'csv_import.dart' show maxCsvBytes;

enum FileShareOutcome { selected, dismissed, unavailable }

/// The only place that talks to the phone's share sheet and file picker.
/// Tests replace it with a fake.
class FileExchange {
  const FileExchange({this.temporaryDirectory = getTemporaryDirectory});

  /// The phone's cache folder. Tests point it at a folder of their own.
  final Future<Directory> Function() temporaryDirectory;

  /// How long an export is left in place after it was made. The app it was
  /// handed to (a cloud drive, a mail app) may still be reading it once the
  /// share sheet has closed, and the sheet does not say when it is done.
  static const exportKeep = Duration(minutes: 10);
  static int _exportSerial = 0;

  Future<Directory> _exportsDirectory() async => Directory(
    '${(await temporaryDirectory()).path}${Platform.pathSeparator}exports',
  );

  /// Writes [bytes] to a temporary file and opens the share sheet, where the
  /// user chooses where it goes (Files, Drive, email, ...). Nothing is sent
  /// anywhere by the app itself.
  Future<FileShareOutcome> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    final dir = await _exportsDirectory();
    await clearOldExports();
    await dir.create(recursive: true);
    final dot = fileName.lastIndexOf('.');
    final stem = dot < 0 ? fileName : fileName.substring(0, dot);
    final extension = dot < 0 ? '' : fileName.substring(dot);
    final unique =
        '$stem-${DateTime.now().microsecondsSinceEpoch}-${_exportSerial++}$extension';
    final file = File('${dir.path}${Platform.pathSeparator}$unique');
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: fileName,
        sharePositionOrigin: origin,
      ),
    );
    // The copy has done its job once the other app has had time to take it.
    // (If the app is closed before then, the next start removes it.)
    Timer(exportKeep + const Duration(seconds: 5), clearOldExports);
    return switch (result.status) {
      ShareResultStatus.success => FileShareOutcome.selected,
      ShareResultStatus.dismissed => FileShareOutcome.dismissed,
      ShareResultStatus.unavailable => FileShareOutcome.unavailable,
    };
  }

  /// Opens the phone's save dialog so the person picks the folder (and may
  /// rename the file), and writes [bytes] there. True when it was saved, false
  /// when they closed the dialog. The app never writes anywhere it was not
  /// pointed at, and remembers no folder.
  Future<bool> saveFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save your backup',
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
    );
    return saved != null;
  }

  /// Deletes every temporary copy made for sharing (they hold financial
  /// data). Report failures so a confirmed erase cannot silently claim success.
  Future<void> clearTemporaryFiles() async {
    final root = await temporaryDirectory();
    var failed = false;
    for (final name in ['exports', 'share_plus', 'file_picker']) {
      try {
        final dir = Directory('${root.path}/$name');
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw const FileSystemException(
        'Temporary financial files could not be cleared.',
      );
    }
  }

  /// Expire both Dart sources and plugin-owned Android attachments. Retain
  /// fresh files so delayed recipients can still read their granted URI.
  Future<void> clearOldExports() async {
    try {
      final root = await temporaryDirectory();
      final cutoff = DateTime.now().subtract(exportKeep);
      for (final name in ['exports', 'share_plus']) {
        final dir = Directory('${root.path}/$name');
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          if (entry is File && (await entry.lastModified()).isBefore(cutoff)) {
            await entry.delete();
          }
        }
        if (await dir.list().isEmpty) await dir.delete();
      }
    } catch (_) {}
  }

  /// Lets the user choose a file and returns its bytes, or null if they
  /// cancel. Throws [BackupFormatException] when the file is far too large.
  Future<Uint8List?> pickFile() => _pick(
    title: 'Choose a backup file',
    limit: maxBackupBytes,
    tooLarge: 'That file is too large to be a backup.',
  );

  /// The same for a CSV file to import (the limit is [maxCsvBytes]).
  Future<Uint8List?> pickCsv() => _pick(
    title: 'Choose a CSV file',
    limit: maxCsvBytes,
    tooLarge: 'That file is too large to import. Split it into smaller parts.',
  );

  Future<Uint8List?> _pick({
    required String title,
    required int limit,
    required String tooLarge,
  }) async {
    final file = await FilePicker.pickFile(dialogTitle: title);
    if (file == null) return null;
    final length = await file.length();
    if (length != null && length > limit) {
      throw BackupFormatException(tooLarge);
    }
    final bytes = await file.readAsBytes();
    // On Android the picker works on a copy in the app's cache; it holds the
    // whole backup, so it goes once the bytes are read.
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
    return bytes;
  }
}
