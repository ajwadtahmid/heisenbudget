import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/theme.dart';
import '../../providers/settings_providers.dart';
import '../shared/appearance_pickers.dart';

/// Theme, accent, text font and Lab flavor.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final c = context.appColors;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          label('Theme'),
          KeyedSubtree(
            key: const ValueKey('theme-mode'),
            child: ThemeModePicker(
              selected: settings.themeMode,
              onChanged: notifier.setThemeMode,
            ),
          ),
          label('Accent'),
          AccentPicker(
            selected: settings.accent,
            onChanged: notifier.setAccent,
          ),
          label('Text font'),
          FontPicker(
            selected: settings.textFont,
            onChanged: notifier.setTextFont,
          ),
          const SizedBox(height: Gap.s),
          Text(
            'Numbers always use Geist Mono so they line up.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('Lab flavor'),
          const SizedBox(height: Gap.s),
          SwitchListTile(
            key: const ValueKey('lab-flavor'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Lab flavor'),
            subtitle: const Text(
              'Playful instrument wording, such as PURITY and flat-line messages.',
            ),
            value: settings.labFlavor,
            onChanged: notifier.setLabFlavor,
          ),
          const SizedBox(height: Gap.s),
          Text(
            'What it changes, and nothing else:',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Gap.xs),
          for (final line in const [
            'Under the balance: PURITY, or SAVED when off.',
            'The chart heading: SPECTRUM, or SPENDING when off.',
            'Empty lists: "Flat line" messages, or plain sentences when off.',
          ])
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(
                '·  $line',
                key: const ValueKey('lab-flavor-effect'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
