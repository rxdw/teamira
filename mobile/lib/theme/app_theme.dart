import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_page_transitions.dart';
import 'palette.dart';
import 'text_styles.dart';

class SeenlyAppTheme {
  const SeenlyAppTheme._();

  // One shared transitions map for light/dark: Android/desktop get
  // Seenly's own fade+rise (see app_page_transitions.dart), iOS/macOS
  // keep the native swipe-to-go-back transition on purpose.
  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: SeenlyPageTransitionsBuilder(),
      TargetPlatform.fuchsia: SeenlyPageTransitionsBuilder(),
      TargetPlatform.linux: SeenlyPageTransitionsBuilder(),
      TargetPlatform.windows: SeenlyPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: SeenlyPalette.background,
      pageTransitionsTheme: _pageTransitions,
      colorScheme: base.colorScheme.copyWith(
        primary: SeenlyPalette.accent,
        onPrimary: SeenlyPalette.accentOnAccent,
        surface: SeenlyPalette.paper,
        error: SeenlyPalette.coral,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: SeenlyPalette.ink,
        displayColor: SeenlyPalette.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SeenlyPalette.background,
        foregroundColor: SeenlyPalette.ink,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SeenlyPalette.accent,
          foregroundColor: SeenlyPalette.accentOnAccent,
          textStyle: SeenlyText.serif(italic: true, size: 14),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SeenlyPalette.paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SeenlyPalette.ink,
        contentTextStyle: SeenlyText.serif(color: SeenlyPalette.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      useMaterial3: true,
    );
  }

  /// Same palette as [light], color for color — dark mode doesn't have
  /// its own look yet, so nothing should visibly change when it's on
  /// except the rabbit mascot swapping to its dark-friendly artwork
  /// (that swap keys off [Brightness.dark], which is why this still
  /// needs to be a real `ThemeData.dark()`-based theme rather than just
  /// reusing [light] outright). When the real dark palette is designed,
  /// only the colors below need to change.
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: SeenlyPalette.background,
      pageTransitionsTheme: _pageTransitions,
      colorScheme: base.colorScheme.copyWith(
        primary: SeenlyPalette.accent,
        onPrimary: SeenlyPalette.accentOnAccent,
        surface: SeenlyPalette.paper,
        error: SeenlyPalette.coral,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: SeenlyPalette.ink,
        displayColor: SeenlyPalette.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SeenlyPalette.background,
        foregroundColor: SeenlyPalette.ink,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SeenlyPalette.accent,
          foregroundColor: SeenlyPalette.accentOnAccent,
          textStyle: SeenlyText.serif(italic: true, size: 14),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SeenlyPalette.paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SeenlyPalette.ink,
        contentTextStyle: SeenlyText.serif(color: SeenlyPalette.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      useMaterial3: true,
    );
  }
}
