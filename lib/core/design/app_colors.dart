import 'package:flutter/material.dart';

/// The interface accent: primary key, selected states, switches, chart focus.
/// Received (green) and Spent (amber) never change with it, so a colour always
/// means the same money event. Amber is not offered: it is the Spent colour.
enum AccentColor {
  assay('Assay teal', dark: Color(0xFF2FD6C0), light: Color(0xFF087569)),
  ice('Ice', dark: Color(0xFF5CC8FF), light: Color(0xFF0B6BA8)),
  violet('Violet', dark: Color(0xFFB69CFF), light: Color(0xFF6A43D6)),
  rose('Rose', dark: Color(0xFFFF8FB1), light: Color(0xFFC2275F)),
  graphite('Graphite', dark: Color(0xFFD7DEDA), light: Color(0xFF2A3330));

  const AccentColor(this.label, {required this.dark, required this.light});

  final String label;
  final Color dark;
  final Color light;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The accent saved under [name], or the default when unknown.
  static AccentColor fromName(String? name) =>
      AccentColor.values.asNameMap()[name] ?? AccentColor.assay;
}

/// Every colour the app draws with, resolved for one brightness and accent.
/// Material's ColorScheme has no slot for most of these, so they travel as a
/// theme extension: `context.appColors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ground,
    required this.panel,
    required this.panelHigh,
    required this.hairline,
    required this.text,
    required this.dim,
    required this.faint,
    required this.received,
    required this.spent,
    required this.spentFill,
    required this.error,
    required this.accent,
    required this.onAccent,
  });

  /// Screen background ("ink" in dark, "bench" in light).
  final Color ground;

  /// Sheets, dialogs, menus: one step off the ground.
  final Color panel;

  /// Selected and raised states: two steps off the ground.
  final Color panelHigh;

  /// 1dp rules. The app uses these instead of shadows.
  final Color hairline;

  final Color text;

  /// Secondary text (labels, dates).
  final Color dim;

  /// Non-text marks only (ticks, leader dots); too light for words.
  final Color faint;

  /// Money in: channel 1.
  final Color received;

  /// Money out and warnings: channel 2 (text-safe).
  final Color spent;

  /// Channel 2 for bars and other non-text fills (a touch brighter in light
  /// mode, still at least 3:1 against the ground).
  final Color spentFill;
  final Color error;
  final Color accent;
  final Color onAccent;

  /// Kept for older call sites: warnings share the Spent channel.
  Color get warning => spent;

  static const _darkGround = Color(0xFF070A09);
  static const _lightGround = Color(0xFFF4F6F5);

  /// The default Ink palette with the Assay teal accent.
  static final dark = resolve(Brightness.dark, AccentColor.assay);

  /// The default Bench palette with the Assay teal accent.
  static final light = resolve(Brightness.light, AccentColor.assay);

  static AppColors resolve(Brightness brightness, AccentColor accent) {
    final isDark = brightness == Brightness.dark;
    return AppColors(
      ground: isDark ? _darkGround : _lightGround,
      panel: isDark ? const Color(0xFF0D1210) : const Color(0xFFFFFFFF),
      panelHigh: isDark ? const Color(0xFF131A17) : const Color(0xFFEBEFED),
      hairline: isDark ? const Color(0xFF26302B) : const Color(0xFFD5DCD8),
      text: isDark ? const Color(0xFFE6EDE9) : const Color(0xFF0C1411),
      dim: isDark ? const Color(0xFF8A9892) : const Color(0xFF55635C),
      faint: isDark ? const Color(0xFF56625C) : const Color(0xFF7C8983),
      received: isDark ? const Color(0xFF3EE08F) : const Color(0xFF0B7A48),
      spent: isDark ? const Color(0xFFFFB547) : const Color(0xFF9A5600),
      spentFill: isDark ? const Color(0xFFFFB547) : const Color(0xFFC47600),
      error: isDark ? const Color(0xFFFF6B57) : const Color(0xFFC2321F),
      accent: accent.forBrightness(brightness),
      onAccent: isDark ? const Color(0xFF04120B) : const Color(0xFFFFFFFF),
    );
  }

  @override
  AppColors copyWith({
    Color? ground,
    Color? panel,
    Color? panelHigh,
    Color? hairline,
    Color? text,
    Color? dim,
    Color? faint,
    Color? received,
    Color? spent,
    Color? spentFill,
    Color? error,
    Color? accent,
    Color? onAccent,
  }) {
    return AppColors(
      ground: ground ?? this.ground,
      panel: panel ?? this.panel,
      panelHigh: panelHigh ?? this.panelHigh,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      faint: faint ?? this.faint,
      received: received ?? this.received,
      spent: spent ?? this.spent,
      spentFill: spentFill ?? this.spentFill,
      error: error ?? this.error,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      ground: mix(ground, other.ground),
      panel: mix(panel, other.panel),
      panelHigh: mix(panelHigh, other.panelHigh),
      hairline: mix(hairline, other.hairline),
      text: mix(text, other.text),
      dim: mix(dim, other.dim),
      faint: mix(faint, other.faint),
      received: mix(received, other.received),
      spent: mix(spent, other.spent),
      spentFill: mix(spentFill, other.spentFill),
      error: mix(error, other.error),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
