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
  const FileExchange();

  /// Writes [bytes] to a temporary file and opens the share sheet, where the
  /// user chooses where it goes (Files, Drive, email, ...). Nothing is sent
  /// anywhere by the app itself.
  Future<void> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}exports',
    );
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
    return file.readAsBytes();
  }
}
