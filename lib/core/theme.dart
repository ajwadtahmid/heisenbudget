import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/app_colors.dart';
import 'design/app_font.dart';

// Everything that styled screens need comes through this one import.
export 'design/app_colors.dart';
export 'design/app_font.dart';

/// Corner radii. Small, like instrument panels: nothing is a pill.
abstract final class Radii {
  static const double chip = 8;
  static const double input = 10;
  static const double panel = 12;
  static const double dialog = 16;
  static const double sheet = 20;
}

/// Spacing on a 4dp grid.
abstract final class Gap {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

ThemeData lightTheme({
  AccentColor accent = AccentColor.assay,
  AppFont font = AppFont.geist,
}) => buildTheme(brightness: Brightness.light, accent: accent, font: font);

ThemeData darkTheme({
  AccentColor accent = AccentColor.assay,
  AppFont font = AppFont.geist,
}) => buildTheme(brightness: Brightness.dark, accent: accent, font: font);

/// The whole look. Depth comes from tonal panels and 1dp hairlines, never
/// shadows; the accent only colours interface chrome.
ThemeData buildTheme({
  required Brightness brightness,
  AccentColor accent = AccentColor.assay,
  AppFont font = AppFont.geist,
}) {
  final c = AppColors.resolve(brightness, accent);
  final isDark = brightness == Brightness.dark;

  Color tint(Color color, double alpha, Color over) =>
      Color.alphaBlend(color.withValues(alpha: alpha), over);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: tint(c.accent, 0.16, c.panel),
    onPrimaryContainer: c.accent,
    secondary: c.dim,
    onSecondary: c.ground,
    secondaryContainer: c.panelHigh,
    onSecondaryContainer: c.text,
    tertiary: c.spent,
    onTertiary: c.ground,
    tertiaryContainer: tint(c.spent, 0.16, c.panel),
    onTertiaryContainer: c.spent,
    error: c.error,
    onError: c.ground,
    errorContainer: tint(c.error, 0.16, c.panel),
    onErrorContainer: c.error,
    surface: c.ground,
    onSurface: c.text,
    onSurfaceVariant: c.dim,
    surfaceDim: c.ground,
    surfaceBright: c.panelHigh,
    surfaceContainerLowest: c.ground,
    surfaceContainerLow: c.panel,
    surfaceContainer: c.panel,
    surfaceContainerHigh: c.panelHigh,
    surfaceContainerHighest: c.panelHigh,
    outline: isDark ? const Color(0xFF3A4742) : const Color(0xFFB3BDB8),
    outlineVariant: c.hairline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: c.text,
    onInverseSurface: c.ground,
    inversePrimary: c.accent,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: font.family,
  );

  // A readable, restrained scale. Labels are tracked caps at 12sp (the floor
  // for small text); everything is sp so it follows the system font size.
  TextStyle? tune(
    TextStyle? style, {
    double? size,
    FontWeight? weight,
    double? spacing,
    double? height,
    Color? color,
  }) => style?.copyWith(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
    color: color,
  );

  final t = base.textTheme;
  final textTheme = t.copyWith(
    titleLarge: tune(t.titleLarge, size: 20, weight: FontWeight.w600),
    titleMedium: tune(t.titleMedium, size: 16, weight: FontWeight.w600),
    titleSmall: tune(t.titleSmall, size: 14, weight: FontWeight.w600),
    bodyLarge: tune(t.bodyLarge, size: 16, height: 1.35),
    bodyMedium: tune(t.bodyMedium, size: 15, height: 1.35),
    bodySmall: tune(t.bodySmall, size: 13, height: 1.3, color: c.dim),
    labelLarge: tune(t.labelLarge, size: 14, weight: FontWeight.w600),
    labelMedium: tune(
      t.labelMedium,
      size: 12,
      weight: FontWeight.w600,
      spacing: 0.9,
      color: c.dim,
    ),
    labelSmall: tune(
      t.labelSmall,
      size: 12,
      weight: FontWeight.w500,
      spacing: 0.6,
      color: c.dim,
    ),
  );

  RoundedRectangleBorder rounded(double radius, {bool rule = true}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: rule ? BorderSide(color: c.hairline) : BorderSide.none,
      );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.input),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    dividerColor: c.hairline,
    splashColor: c.accent.withValues(alpha: 0.10),
    highlightColor: c.accent.withValues(alpha: 0.06),
    extensions: [c],
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: c.text),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.input),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelSmall?.copyWith(
          letterSpacing: 0.4,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? c.accent : c.dim,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? c.accent : c.dim,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      // Quiet: a tonal fill and a thin accent outline, not a solid slab.
      backgroundColor: scheme.primaryContainer,
      foregroundColor: c.accent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.input),
        side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
      ),
      extendedTextStyle: textTheme.labelLarge?.copyWith(letterSpacing: 1.1),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.input),
        ),
        textStyle: textTheme.labelLarge,
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: const Size(48, 48),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.input),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: inputBorder(scheme.outline),
      enabledBorder: inputBorder(scheme.outline),
      disabledBorder: inputBorder(c.hairline),
      focusedBorder: inputBorder(c.accent, 1.5),
      errorBorder: inputBorder(c.error),
      focusedErrorBorder: inputBorder(c.error, 1.5),
      labelStyle: textTheme.bodyMedium?.copyWith(color: c.dim),
      floatingLabelStyle: textTheme.bodySmall?.copyWith(color: c.accent),
      helperStyle: textTheme.bodySmall,
      hintStyle: textTheme.bodyMedium?.copyWith(color: c.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primaryContainer,
      disabledColor: Colors.transparent,
      side: BorderSide(color: c.hairline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      labelStyle: textTheme.labelLarge?.copyWith(
        color: c.text,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: c.accent),
      checkmarkColor: c.accent,
      iconTheme: IconThemeData(color: c.dim, size: 18),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.input),
          ),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.text,
        ),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.panel,
      modalBackgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dragHandleColor: c.faint,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
        side: BorderSide(color: c.hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rounded(Radii.dialog),
      titleTextStyle: textTheme.titleLarge?.copyWith(color: c.text),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.panelHigh,
      elevation: 0,
      actionTextColor: c.accent,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.text),
      shape: rounded(Radii.input),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panelHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rounded(Radii.input),
      textStyle: textTheme.bodyMedium?.copyWith(color: c.text),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.panelHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(rounded(Radii.input)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.dim,
      textColor: c.text,
      titleTextStyle: textTheme.bodyLarge?.copyWith(color: c.text),
      subtitleTextStyle: textTheme.bodySmall,
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: c.accent,
      labelColor: c.accent,
      unselectedLabelColor: c.dim,
      dividerColor: c.hairline,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.panelHigh,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: c.hairline),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: c.text),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.onAccent : c.dim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.accent : c.panelHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.accent : scheme.outline,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    // The parts users touch but designers forget: caret and selection.
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.28),
      selectionHandleColor: c.accent,
    ),
  );
}
