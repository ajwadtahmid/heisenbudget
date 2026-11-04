import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late Directory exports;
  late FileExchange exchange;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('hb_cache');
    exports = Directory('${cache.path}${Platform.pathSeparator}exports');
    await exports.create();
    exchange = FileExchange(temporaryDirectory: () async => cache);
  });
  tearDown(() => cache.delete(recursive: true));

  Future<File> export(String name, {required Duration age}) async {
    final file = File('${exports.path}${Platform.pathSeparator}$name');
    await file.writeAsString('financial data');
    await file.setLastModified(DateTime.now().subtract(age));
    return file;
  }

  group('exports left in the cache after sharing', () {
    test('confirmed erase also removes nested picker import copies', () async {
      final pick = await Directory('${cache.path}/file_picker/42')
          .create(recursive: true);
      final imported = await File('${pick.path}/private-backup.json')
          .writeAsString('private import');
      await exchange.clearTemporaryFiles();
      expect(await imported.exists(), isFalse);
      expect(await Directory('${cache.path}/file_picker').exists(), isFalse);
    });
    test('a later same-name export preserves the first source with a unique identity', () async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final paths = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            paths.add(
              ((call.arguments as Map)['paths'] as List).single as String,
            );
            return 'chosen.recipient';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final byte in [1, 2]) {
        await exchange.shareFile(
          fileName: 'same.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList([byte]),
        );
      }
      expect(paths.toSet(), hasLength(2));
      expect(await File(paths.first).readAsBytes(), [1]);
      expect(await File(paths.last).readAsBytes(), [2]);
    });
    test(
      'plugin copies expire too, and erase removes fresh plugin attachments',
      () async {
        final native = await Directory('${cache.path}/share_plus').create();
        final old = await File('${native.path}/old.json')
            .writeAsString('old private data');
        await old.setLastModified(
          DateTime.now().subtract(FileExchange.exportKeep * 2),
        );
        final fresh = await File('${native.path}/fresh.json')
            .writeAsString('fresh private data');
        await exchange.clearOldExports();
        expect(await old.exists(), isFalse);
        expect(await fresh.exists(), isTrue);
        await exchange.clearTemporaryFiles();
        expect(await fresh.exists(), isFalse);
        expect(await native.exists(), isFalse);
      },
    );
    test(
      'the ones older than the keep time are deleted, new ones stay',
      () async {
        final old = await export('old.json', age: FileExchange.exportKeep * 2);
        final fresh = await export(
          'fresh.json',
          age: const Duration(minutes: 1),
        );

        await exchange.clearOldExports();

        expect(await old.exists(), isFalse);
        expect(
          await fresh.exists(),
          isTrue,
          reason: 'the other app may be reading',
        );
      },
    );

    test('the folder goes too once it is empty', () async {
      await export('a.json', age: FileExchange.exportKeep * 2);
      await export('b.csv', age: FileExchange.exportKeep * 3);

      await exchange.clearOldExports();

      expect(await exports.exists(), isFalse);
    });

    test('a file just under the keep time is still kept', () async {
      final file = await export(
        'edge.json',
        age: FileExchange.exportKeep - const Duration(minutes: 1),
      );
      await exchange.clearOldExports();
      expect(await file.exists(), isTrue);
    });

    test('nothing to clear, or no folder, is fine', () async {
      await exchange.clearOldExports(); // an empty folder is removed
      expect(await exports.exists(), isFalse);
      await exchange.clearOldExports(); // and with no folder there is no work
      await exchange.clearTemporaryFiles();
    });

    test('clearing everything removes even a fresh export', () async {
      final fresh = await export('fresh.json', age: Duration.zero);
      await exchange.clearTemporaryFiles();
      expect(await fresh.exists(), isFalse);
      expect(await exports.exists(), isFalse);
    });

    test(
      'expiry is best effort but explicit erase reports cache failures',
      () async {
        final broken = FileExchange(
          temporaryDirectory: () async => throw const FileSystemException('x'),
        );
        await broken.clearOldExports();
        await expectLater(
          broken.clearTemporaryFiles(),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}
