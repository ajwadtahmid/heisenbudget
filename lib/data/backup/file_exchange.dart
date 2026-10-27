import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_data.dart';

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

  Future<Directory> _exportsDirectory() async => Directory(
    '${(await temporaryDirectory()).path}${Platform.pathSeparator}exports',
  );

  /// Writes [bytes] to a temporary file and opens the share sheet, where the
  /// user chooses where it goes (Files, Drive, email, ...). Nothing is sent
  /// anywhere by the app itself.
  Future<void> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    final dir = await _exportsDirectory();
    // Drop earlier exports so old financial data does not pile up in cache.
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: fileName,
        sharePositionOrigin: origin,
      ),
    );
    // The copy has done its job once the other app has had time to take it.
    // (If the app is closed before then, the next start removes it.)
    Timer(exportKeep + const Duration(seconds: 5), clearOldExports);
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
  /// data). Best effort: a failure here is not worth showing.
  Future<void> clearTemporaryFiles() async {
    try {
      final dir = await _exportsDirectory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Deletes the temporary copies that are older than [exportKeep]. Run when
  /// the app starts and each time it is opened again. Best effort.
  Future<void> clearOldExports() async {
    try {
      final dir = await _exportsDirectory();
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(exportKeep);
      await for (final entry in dir.list()) {
        if (entry is File && (await entry.lastModified()).isBefore(cutoff)) {
          await entry.delete();
        }
      }
      if (await dir.list().isEmpty) await dir.delete();
    } catch (_) {}
  }

  /// Lets the user choose a file and returns its bytes, or null if they
  /// cancel. Throws [BackupFormatException] when the file is far too large.
  Future<Uint8List?> pickFile() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a backup file');
    if (file == null) return null;
    final length = await file.length();
    if (length != null && length > maxBackupBytes) {
      throw const BackupFormatException(
        'That file is too large to be a backup.',
      );
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
