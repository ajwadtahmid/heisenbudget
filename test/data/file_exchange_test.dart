import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';

void main() {
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

    test('a failing cache folder is not an error', () async {
      final broken = FileExchange(
        temporaryDirectory: () async => throw const FileSystemException('x'),
      );
      await broken.clearOldExports();
      await broken.clearTemporaryFiles();
    });
  });
}
