import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/settings_providers.dart';

/// Adds the bundled fonts' licences to the app's licence page.
void _registerFontLicences() {
  const files = {
    'Geist and Geist Mono': 'assets/fonts/licenses/Geist-OFL.txt',
    'Inter': 'assets/fonts/licenses/Inter-OFL.txt',
    'Atkinson Hyperlegible':
        'assets/fonts/licenses/AtkinsonHyperlegible-OFL.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in files.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicences();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const HeisenbudgetApp(),
    ),
  );
}
