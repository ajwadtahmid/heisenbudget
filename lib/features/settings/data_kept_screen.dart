import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// A plain-language page on where the data lives.
class DataKeptScreen extends StatelessWidget {
  const DataKeptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const points = [
      (
        'It stays on this phone.',
        'Your transactions, categories and settings are stored here and '
            'nowhere else.',
      ),
      (
        'No account, no internet.',
        '$appName never connects to the internet, and has no sign-in, '
            'analytics or advertising.',
      ),
      (
        'Files leave only when you send them.',
        'Back up and Export to CSV make a file and open your phone\'s share '
            'sheet. Where it goes is your choice.',
      ),
      (
        'Deleting the app deletes the data.',
        'Back up first if you might want it again. Restore brings a backup '
            'file back, here or on a new phone.',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('How your data is kept')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          for (final (heading, body) in points) ...[
            Text(heading, style: theme.textTheme.titleSmall),
            const SizedBox(height: Gap.xs),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.l),
          ],
        ],
      ),
    );
  }
}
