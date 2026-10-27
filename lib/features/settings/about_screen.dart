import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/design/section_label.dart';
import '../../core/theme.dart';

/// What the app is, which version, where the privacy policy is, and how the
/// data is kept.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: privacyPolicyUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    const kept = [
      (
        'It stays on this phone.',
        'Your transactions, categories and settings are stored here. '
            '$appName has no server and sends them nowhere. If your phone\'s '
            'own backup (Google on Android, iCloud on iPhone) is switched on, '
            'it may keep a copy in your account; that is between you and '
            'Google or Apple.',
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
      appBar: AppBar(title: const Text('About $appName')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            appName,
            key: const ValueKey('about-name'),
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            'Version $appVersion',
            key: const ValueKey('about-version'),
            style: monoText(size: 14, color: c.dim),
          ),
          const SizedBox(height: Gap.l),
          Text(
            'A simple, private expense and income tracker. Log what you spend '
            'and earn, plan with monthly budgets, and see where your money '
            'goes. It works completely offline, with no account.',
            key: const ValueKey('about-description'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Privacy policy'),
          const SizedBox(height: Gap.m),
          Text(
            'The full policy is on the developer\'s site:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.s),
          SelectableText(
            privacyPolicyUrl,
            key: const ValueKey('about-privacy-url'),
            style: monoText(size: 13, color: c.accent),
          ),
          const SizedBox(height: Gap.s),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('about-copy-link'),
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy link'),
            ),
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Open-source licences'),
          const SizedBox(height: Gap.m),
          Text(
            'Built with Flutter, drift, Riverpod and other open-source '
            'software, and the Geist, Inter and Atkinson Hyperlegible fonts.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.s),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('about-licences'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: appVersion,
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('View licences'),
            ),
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('How your data is kept'),
          const SizedBox(height: Gap.m),
          for (final (heading, body) in kept) ...[
            Text(heading, style: theme.textTheme.titleSmall),
            const SizedBox(height: Gap.xs),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.l),
          ],
          Text(
            'Not affiliated with or endorsed by any TV show or its owners.',
            key: const ValueKey('about-disclaimer'),
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
        ],
      ),
    );
  }
}
