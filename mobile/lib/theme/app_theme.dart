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

  static ThemeData get light => _build(base: ThemeData.light(useMaterial3: true), colors: SeenlyPalette.lightColors);

  /// The real dark palette — see the note at the top of palette.dart for
  /// the "evening lamp" idea behind the colors themselves.
  static ThemeData get dark => _build(base: ThemeData.dark(useMaterial3: true), colors: SeenlyPalette.darkColors);

  // Shared builder: [light] and [dark] are built at the same time
  // regardless of which one is actually active right now (Flutter holds
  // both simultaneously and picks based on the device/app brightness), so
  // this deliberately takes an explicit color set rather than reading the
  // ambient SeenlyPalette.x getters — those would just return whichever
  // one happens to be current and give both themes the same colors.
  static ThemeData _build({required ThemeData base, required SeenlyColorSet colors}) {
    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      pageTransitionsTheme: _pageTransitions,
      colorScheme: base.colorScheme.copyWith(
        primary: colors.accent,
        onPrimary: colors.accentOnAccent,
        surface: colors.paper,
        error: colors.coral,
        brightness: base.brightness,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.ink,
        displayColor: colors.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.accentOnAccent,
          textStyle: SeenlyText.serif(italic: true, size: 14, color: colors.accentOnAccent),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: SeenlyText.serif(color: colors.placeholder),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: SeenlyText.serif(color: colors.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      useMaterial3: true,
    );
  }
}
