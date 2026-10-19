import 'package:flutter/material.dart';

// ── Dark palette ──────────────────────────────────────────────────────────────
const glassNavy0 = Color(0xFF071427);
const glassNavy1 = Color(0xFF0B1F3A);
const glassNavy2 = Color(0xFF12294A);
const glassBlue = Color(0xFF14B8A6);
const glassBlueDark = Color(0xFF0F766E);
const glassBlueGlow = Color(0x5914B8A6);
const glassDanger = Color(0xFFFF6B6B);
const glassSuccess = Color(0xFF4ADE80);
const glassWarning = Color(0xFFFFB347);

// ── Light palette ─────────────────────────────────────────────────────────────
const glassLightBg0 = Color(0xFFFFFFFF);
const glassLightBg1 = Color(0xFFF6FAFB);
const glassLightBg2 = Color(0xFFEEF5F7);
const glassTextDark = Color(0xFF0B1F3A);

// ── Legacy surface helpers (dark-only) ────────────────────────────────────────
Color glassSurface([double opacity = 0.07]) => Colors.white.withOpacity(opacity);
Color glassBorder([double opacity = 0.13]) => Colors.white.withOpacity(opacity);
Color glassText([double opacity = 1.0]) => Colors.white.withOpacity(opacity);

// ── Theme-adaptive colour helpers ─────────────────────────────────────────────
/// Use `context.onSurface(alpha)` instead of `Colors.white.withValues(alpha: x)`
/// for text, icons, and subtle decoration so they adapt to light/dark mode.
extension GlassColorX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color onSurface([double alpha = 1.0]) =>
      (isDark ? Colors.white : glassTextDark).withValues(alpha: alpha);

  Color surfaceTint([double alpha = 0.10]) =>
      (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

// ── Dark theme ────────────────────────────────────────────────────────────────
ThemeData buildGlassTheme() {
  const colorScheme = ColorScheme.dark(
    primary: glassBlue,
    onPrimary: Colors.white,
    secondary: glassBlue,
    onSecondary: Colors.white,
    surface: glassNavy1,
    onSurface: Colors.white,
    error: glassDanger,
    onError: Colors.white,
    surfaceContainerLow: Color(0x12FFFFFF),
    surfaceContainerHigh: Color(0x18FFFFFF),
    outline: Color(0x21FFFFFF),
    outlineVariant: Color(0x14FFFFFF),
    onSurfaceVariant: Color(0x99FFFFFF),
    primaryContainer: Color(0x3314B8A6),
    onPrimaryContainer: glassBlue,
    errorContainer: Color(0x33FF6B6B),
    onErrorContainer: glassDanger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: glassNavy0,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -1.0),
      displayMedium: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      headlineSmall:
          TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Color(0x99FFFFFF)),
      labelLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2),
      labelMedium: TextStyle(
          color: Color(0x99FFFFFF), fontWeight: FontWeight.w500),
      labelSmall: TextStyle(
          color: Color(0x61FFFFFF), fontWeight: FontWeight.w500),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: Color(0x3314B8A6),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: glassBlue, size: 22);
        }
        return const IconThemeData(color: Color(0x80FFFFFF), size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
              color: glassBlue, fontSize: 11, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: Color(0x80FFFFFF), fontSize: 11);
      }),
    ),
    cardTheme: CardThemeData(
      color: Color(0x12FFFFFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x21FFFFFF), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x0FFFFFFF),
      hintStyle: const TextStyle(color: Color(0x59FFFFFF)),
      labelStyle: const TextStyle(color: Color(0x99FFFFFF)),
      floatingLabelStyle: const TextStyle(color: glassBlue),
      prefixIconColor: const Color(0x80FFFFFF),
      suffixIconColor: const Color(0x80FFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x21FFFFFF), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x21FFFFFF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassDanger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassDanger, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: glassBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: glassBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0x40FFFFFF), width: 1),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: glassBlue,
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0x80FFFFFF);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? glassBlue
            : const Color(0x26FFFFFF);
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? glassBlue
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: Color(0x59FFFFFF), width: 1.5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: glassBlue,
      inactiveTrackColor: const Color(0x26FFFFFF),
      thumbColor: Colors.white,
      overlayColor: const Color(0x3314B8A6),
      valueIndicatorColor: glassBlue,
      valueIndicatorTextStyle:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x17FFFFFF),
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      textColor: Colors.white,
      iconColor: const Color(0x99FFFFFF),
    ),
    iconTheme: const IconThemeData(color: Color(0xCCFFFFFF)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF16304F),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF12294A),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
      contentTextStyle: const TextStyle(color: Color(0xBFFFFFFF)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0x14FFFFFF),
      labelStyle: const TextStyle(color: Colors.white),
      side: const BorderSide(color: Color(0x21FFFFFF)),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: glassBlue),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: glassBlueDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

// ── Light theme ───────────────────────────────────────────────────────────────
ThemeData buildGlassThemeLight() {
  const onSurface = glassTextDark;
  const onSurfaceVariant = Color(0x99000000);

  const colorScheme = ColorScheme.light(
    primary: glassBlueDark,
    onPrimary: Colors.white,
    secondary: glassBlueDark,
    onSecondary: Colors.white,
    surface: glassLightBg0,
    onSurface: onSurface,
    error: glassDanger,
    onError: Colors.white,
    surfaceContainerLow: Color(0x0F000000),
    surfaceContainerHigh: Color(0x1A000000),
    outline: Color(0x29000000),
    outlineVariant: Color(0x14000000),
    onSurfaceVariant: onSurfaceVariant,
    primaryContainer: Color(0x2014B8A6),
    onPrimaryContainer: Color(0xFF0F766E),
    errorContainer: Color(0x20FF6B6B),
    onErrorContainer: glassDanger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: glassLightBg0,
    textTheme: const TextTheme(
      displayLarge:  TextStyle(color: onSurface, fontWeight: FontWeight.w700, letterSpacing: -1.0),
      displayMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium:TextStyle(color: onSurface, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      headlineSmall: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      titleLarge:    TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      titleMedium:   TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      titleSmall:    TextStyle(color: onSurface, fontWeight: FontWeight.w500),
      bodyLarge:     TextStyle(color: onSurface),
      bodyMedium:    TextStyle(color: onSurface),
      bodySmall:     TextStyle(color: onSurfaceVariant),
      labelLarge:    TextStyle(color: onSurface, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium:   TextStyle(color: onSurfaceVariant, fontWeight: FontWeight.w500),
      labelSmall:    TextStyle(color: Color(0x61000000), fontWeight: FontWeight.w500),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      indicatorColor: Color(0x2014B8A6),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: glassBlueDark, size: 22);
        }
        return const IconThemeData(color: Color(0x80000000), size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: glassBlueDark, fontSize: 11, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: Color(0x80000000), fontSize: 11);
      }),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xB3FFFFFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x14000000), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x0A000000),
      hintStyle: const TextStyle(color: Color(0x66000000)),
      labelStyle: const TextStyle(color: onSurfaceVariant),
      floatingLabelStyle: const TextStyle(color: glassBlueDark),
      prefixIconColor: onSurfaceVariant,
      suffixIconColor: onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x29000000), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x29000000), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassBlueDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassDanger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: glassDanger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: glassBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: glassBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: const BorderSide(color: Color(0x40000000), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: glassBlueDark,
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0x80000000);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? glassBlueDark
            : const Color(0x26000000);
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? glassBlueDark
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: Color(0x66000000), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: glassBlueDark,
      inactiveTrackColor: const Color(0x26000000),
      thumbColor: glassBlueDark,
      overlayColor: const Color(0x2014B8A6),
      valueIndicatorColor: glassBlueDark,
      valueIndicatorTextStyle:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x14000000),
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      textColor: onSurface,
      iconColor: onSurfaceVariant,
    ),
    iconTheme: const IconThemeData(color: Color(0xCC000000)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFFE8EEFF),
      contentTextStyle: const TextStyle(color: onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: glassLightBg0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
          color: onSurface, fontSize: 18, fontWeight: FontWeight.w600),
      contentTextStyle: const TextStyle(color: onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0x0F000000),
      labelStyle: const TextStyle(color: onSurface),
      side: const BorderSide(color: Color(0x1F000000)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: glassBlueDark),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: glassBlueDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}
