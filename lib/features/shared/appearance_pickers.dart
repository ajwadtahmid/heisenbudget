import 'package:flutter/material.dart';

import '../../core/currencies.dart';
import '../../core/theme.dart';

/// System / Light / Dark. Shared by Settings and the first-run welcome.
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      ThemeMode.system: 'System',
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
    };
    // A segmented bar cannot wrap. At large text sizes use chips, which can
    // flow onto a second line instead of overflowing.
    final large = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    if (large) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final mode in ThemeMode.values)
            ChoiceChip(
              key: ValueKey('theme-${mode.name}'),
              label: Text(labels[mode]!),
              selected: mode == selected,
              onSelected: (_) => onChanged(mode),
            ),
        ],
      );
    }
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto),
          label: Text('System'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode),
          label: Text('Dark'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// The interface accent: a row of colour swatches. Each is a 48dp target with
/// a ring on the chosen one and a spoken name.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AccentColor selected;
  final ValueChanged<AccentColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final c = context.appColors;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final accent in AccentColor.values)
          Semantics(
            button: true,
            selected: accent == selected,
            label: '${accent.label} accent',
            child: ExcludeSemantics(
              child: InkResponse(
                key: ValueKey('accent-${accent.name}'),
                onTap: () => onChanged(accent),
                radius: 28,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent == selected
                              ? c.text
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.forBrightness(brightness),
                        ),
                        child: accent == selected
                            ? Icon(Icons.check, size: 16, color: c.ground)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The text font, as a one-line drop-down. Every entry (and the closed field)
/// is drawn in its own face so you can compare. Numbers always stay in Geist
/// Mono.
class FontPicker extends StatelessWidget {
  const FontPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppFont selected;
  final ValueChanged<AppFont> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<AppFont>(
      key: const ValueKey('font-dropdown'),
      initialSelection: selected,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      textStyle: TextStyle(fontFamily: selected.family, fontSize: 16),
      dropdownMenuEntries: [
        for (final font in AppFont.values)
          DropdownMenuEntry(
            value: font,
            label: font.label,
            labelWidget: Text(
              font.label,
              style: TextStyle(fontFamily: font.family, fontSize: 16),
            ),
          ),
      ],
      onSelected: (font) {
        if (font != null) onChanged(font);
      },
    );
  }
}

/// Searchable currency list ("bang" finds Bangladeshi Taka). Shared by
/// Settings and the welcome tour.
class CurrencyDropdown extends StatelessWidget {
  const CurrencyDropdown({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Currency selected;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<Currency>(
      initialSelection: selected,
      label: const Text('Currency'),
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      enableFilter: true,
      requestFocusOnTap: true,
      filterCallback: (entries, text) {
        final query = text.trim().toLowerCase();
        return [
          for (final e in entries)
            if (e.label.toLowerCase().contains(query)) e,
        ];
      },
      dropdownMenuEntries: [
        for (final c in currenciesByName)
          DropdownMenuEntry(
            value: c,
            label: c.label,
            labelWidget: Text(c.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onSelected: (c) {
        if (c != null) onChanged(c);
      },
    );
  }
}
