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

  test('iOS says "no non-exempt encryption" only while the app has none', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
    // Adding encryption (locked backups, an encrypted database) makes that
    // answer wrong: decide the export-compliance answer, then change this test.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final name in [
      'cryptography',
      'pointycastle',
      'encrypt:',
      'sqlcipher',
      'sqlite3mc',
      'flutter_secure_storage',
    ]) {
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

  test('the app id is ours on Android and iOS, not the template one', () {
    const id = 'com.ajwadtahmid.heisenbudget';
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "$id"'));
    expect(gradle, contains('applicationId = "$id"'));
    // The manifest's .MainActivity resolves against the namespace.
    expect(
      File(
        'android/app/src/main/kotlin/com/ajwadtahmid/heisenbudget/MainActivity.kt',
      ).readAsStringSync(),
      startsWith('package $id'),
    );
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = $id;'));
    expect(project, isNot(contains('com.example')));
  });

  group('the logo and the launcher icons', () {
    /// A PNG's width and height, from its header.
    (int, int) pngSize(String path) {
      final b = File(path).readAsBytesSync();
      expect(b.sublist(1, 4), [0x50, 0x4E, 0x47], reason: '$path is a PNG');
      int word(int at) =>
          (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
      return (word(16), word(20));
    }

    test('the vector source has the three parts the icon script needs', () {
      final svg = File('assets/logos/logo.svg').readAsStringSync();
      expect(RegExp(r'<path\b').allMatches(svg), hasLength(3));
      expect(svg, contains('<rect'), reason: 'the ground colour');
    });

    test('only the small logo is bundled in the app', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/logos/logo.png'));
      // Declared assets only (the comment explaining why may name the file).
      final declared = RegExp(
        r'^\s*-\s*(assets/\S+)',
        multiLine: true,
      ).allMatches(pubspec).map((m) => m.group(1)!).toList();
      expect(declared, contains('assets/logos/logo.png'));
      expect(declared, isNot(contains('assets/logos/logo.svg')));
      expect(declared.any((a) => a.contains('google_play_icon')), isFalse);
      expect(File('assets/logos/logo.png').lengthSync(), lessThan(100 * 1024));
      expect(File(appLogoAsset).existsSync(), isTrue);
    });

    test('the Google Play icon is 512 by 512', () {
      expect(pngSize('assets/logos/google_play_icon_512.png'), (512, 512));
      expect(
        File('assets/logos/google_play_icon_512.png').lengthSync(),
        lessThan(1024 * 1024),
        reason: 'Play accepts up to 1 MB',
      );
    });

    test('every iOS icon size exists, and none has transparency', () {
      final dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final contents = File('$dir/Contents.json').readAsStringSync();
      for (final name in RegExp(
        r'"filename"\s*:\s*"([^"]+)"',
      ).allMatches(contents).map((m) => m.group(1)!)) {
        final bytes = File('$dir/$name').readAsBytesSync();
        // Colour type 2 is RGB: no alpha channel (the App Store refuses one).
        expect(bytes[25], 2, reason: '$name must be opaque RGB');
      }
      expect(pngSize('$dir/Icon-App-1024x1024@1x.png'), (1024, 1024));
    });

    test('Android has the adaptive layers and the Android 13 themed layer', () {
      const sizes = {
        'mdpi': 108,
        'hdpi': 162,
        'xhdpi': 216,
        'xxhdpi': 324,
        'xxxhdpi': 432,
      };
      sizes.forEach((density, size) {
        for (final layer in [
          'ic_launcher_foreground',
          'ic_launcher_monochrome',
        ]) {
          expect(
            pngSize('android/app/src/main/res/mipmap-$density/$layer.png'),
            (size, size),
            reason: '$layer $density',
          );
        }
      });
      final xml = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(xml, contains('<foreground'));
      expect(
        xml,
        contains(
          '<monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>',
        ),
      );
    });
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
