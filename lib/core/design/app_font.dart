import 'package:flutter/painting.dart';

/// The UI text font the user can choose. All are bundled with the app (no
/// download): see `assets/fonts` and the licences next to them.
enum AppFont {
  geist('Geist', family: 'Geist'),
  inter('Inter', family: 'Inter'),
  atkinson('Atkinson Hyperlegible', family: 'AtkinsonHyperlegible'),

  /// The phone's own font (also what fills in for scripts the others lack,
  /// such as Bengali).
  system('System', family: null);

  const AppFont(this.label, {required this.family});

  final String label;

  /// Flutter font family; null means "use the platform's font".
  final String? family;

  static AppFont fromName(String? name) =>
      AppFont.values.asNameMap()[name] ?? AppFont.geist;
}

/// Numbers always use Geist Mono, whatever text font is chosen, so every
/// readout looks the same and digits never shift as values change.
const monoFamily = 'GeistMono';

TextStyle monoText({
  double size = 15,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
