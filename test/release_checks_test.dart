import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';

/// Guards the "100% offline" promise: no network permission, no network
/// packages, no network code.
void main() {
  test('the main Android manifest has no INTERNET permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });

  test('pubspec has no networking, analytics or font-download packages', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    const banned = [
      'http:',
      'dio:',
      'web_socket_channel:',
      'firebase_',
      'sentry',
      'google_fonts:',
      'package_info_plus:',
      'url_launcher:',
    ];
    for (final name in banned) {
      expect(pubspec, isNot(contains(name)), reason: 'found "$name"');
    }
  });

  test('app code does not touch the network', () {
    final offenders = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      if (RegExp(
        r'HttpClient|package:http|package:dio|WebSocket|Socket\.connect',
      ).hasMatch(text)) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(appVersion, version.group(1));
  });

  test('the app name is Heisenbudget everywhere users can see it', () {
    expect(appName, 'Heisenbudget');
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="Heisenbudget"'),
    );
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<string>Heisenbudget</string>'),
    );
  });

  group('bundled fonts', () {
    const files = [
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'GeistMono-Regular.ttf',
      'GeistMono-Medium.ttf',
      'GeistMono-SemiBold.ttf',
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
      'AtkinsonHyperlegible-Regular.ttf',
      'AtkinsonHyperlegible-Bold.ttf',
    ];

    test('every font file exists and is declared in pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final name in files) {
        expect(File('assets/fonts/$name').existsSync(), isTrue, reason: name);
        expect(pubspec, contains('assets/fonts/$name'), reason: name);
      }
    });

    test('every font family the app can pick is declared', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final family in [
        'Geist',
        'GeistMono',
        'Inter',
        'AtkinsonHyperlegible',
      ]) {
        expect(pubspec, contains('family: $family'), reason: family);
      }
    });

    test('each family ships its licence, and the licences are bundled', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/licenses/'));
      for (final licence in [
        'Geist-OFL.txt',
        'Inter-OFL.txt',
        'AtkinsonHyperlegible-OFL.txt',
      ]) {
        final file = File('assets/fonts/licenses/$licence');
        expect(file.existsSync(), isTrue, reason: licence);
        expect(
          file.readAsStringSync(),
          contains('SIL OPEN FONT LICENSE'),
          reason: licence,
        );
      }
    });

    test('fonts are only ever bundled, never fetched at run time', () {
      // Covered by the banned google_fonts package above; this checks the
      // total size stays sensible for an app that ships the files itself.
      var bytes = 0;
      for (final name in files) {
        bytes += File('assets/fonts/$name').lengthSync();
      }
      expect(bytes, lessThan(4 * 1024 * 1024));
    });
  });
}
