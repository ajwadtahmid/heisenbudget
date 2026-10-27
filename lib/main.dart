import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_bootstrap.dart';
import 'core/error_handling.dart';

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
  installErrorHandlers();
  _registerFontLicences();
  final prefs = await SharedPreferences.getInstance();
  // Opens the data first; if that fails, a recovery screen runs instead.
  runApp(AppBootstrap(prefs: prefs));
}
