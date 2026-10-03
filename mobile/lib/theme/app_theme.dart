import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_page_transitions.dart';
import 'palette.dart';
import 'text_styles.dart';
import 'seenly_skin.dart';

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
    final clay = SeenlySkin.isClay;
    final cozy = SeenlySkin.isCozy;
    // Clay: fat radii everywhere, no hairline borders (a puffy object has no
    // outline — its edge is defined by light and shade), tinted shadows.
    final wellFill = Color.alphaBlend(colors.cork.withOpacity(0.55), colors.paper);
    final clayInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: BorderSide.none,
    );

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
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.accentOnAccent,
          textStyle: clay
              ? SeenlyText.serif(size: 15, weight: FontWeight.w800, color: colors.accentOnAccent)
              : SeenlyText.serif(italic: true, size: 14, color: colors.accentOnAccent),
          padding: EdgeInsets.symmetric(vertical: clay ? 16 : 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(clay ? 28 : 24),
          ),
          elevation: clay ? 6 : 0,
          shadowColor: clay ? colors.accent.withOpacity(0.55) : null,
        ),
      ),
      filledButtonTheme: clay
          ? FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.accentOnAccent,
                textStyle: SeenlyText.serif(size: 15, weight: FontWeight.w800),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
            )
          : null,
      textButtonTheme: clay
          ? TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                textStyle: SeenlyText.serif(size: 14, weight: FontWeight.w800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            )
          : null,
      floatingActionButtonTheme: clay
          ? FloatingActionButtonThemeData(
              backgroundColor: colors.accent,
              foregroundColor: colors.accentOnAccent,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            )
          : null,
      cardTheme: CardThemeData(
        color: colors.paper,
        elevation: clay ? 7 : (cozy ? 0 : 1),
        margin: const EdgeInsets.symmetric(vertical: 6),
        shadowColor: clay
            ? colors.shadowColor.withOpacity(0.5)
            : colors.shadowColor.withOpacity(colors.shadowOpacity),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(clay ? 30 : (cozy ? 22 : 14)),
          side: clay
              ? BorderSide.none
              : BorderSide(
                  color: colors.border.withOpacity(cozy ? 0.75 : 1),
                  width: cozy ? 0.7 : 1,
                ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: clay ? colors.border : colors.border.withOpacity(cozy ? 0.7 : 1),
        thickness: clay ? 1.5 : 0.8,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: clay ? 14 : (cozy ? 0 : 6),
        shadowColor: clay ? colors.shadowColor.withOpacity(0.55) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(clay ? 36 : (cozy ? 26 : 18)),
          side: clay ? BorderSide.none : BorderSide(color: colors.border.withOpacity(0.8)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.paper,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.paper,
        elevation: clay ? 16 : (cozy ? 0 : 4),
        shadowColor: clay ? colors.shadowColor.withOpacity(0.55) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(clay ? 40 : (cozy ? 30 : 20)),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.paper,
        selectedColor: clay ? colors.accent : colors.accent.withOpacity(0.14),
        side: clay ? BorderSide.none : BorderSide(color: colors.border),
        elevation: clay ? 3 : null,
        shadowColor: clay ? colors.shadowColor.withOpacity(0.5) : null,
        shape: clay
            ? const StadiumBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cozy ? 18 : 12),
              ),
        labelStyle: clay
            ? SeenlyText.serif(size: 13, weight: FontWeight.w800, color: colors.inkMuted)
            : SeenlyText.serif(size: 13, color: colors.inkMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: clay ? wellFill : colors.paper,
        contentPadding: EdgeInsets.symmetric(horizontal: clay ? 22 : 18, vertical: clay ? 17 : 15),
        border: clay
            ? clayInputBorder
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(cozy ? 20 : 14),
                borderSide: BorderSide(color: colors.border.withOpacity(0.8), width: 0.8),
              ),
        enabledBorder: clay
            ? clayInputBorder
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(cozy ? 20 : 14),
                borderSide: BorderSide(color: colors.border.withOpacity(0.8), width: 0.8),
              ),
        focusedBorder: clay
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: BorderSide(color: colors.accent.withOpacity(0.75), width: 2.2),
              )
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(cozy ? 20 : 14),
                borderSide: BorderSide(color: colors.accent.withOpacity(0.65), width: 1.2),
              ),
        hintStyle: SeenlyText.serif(color: colors.placeholder),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: SeenlyText.serif(color: colors.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(clay ? 24 : 12),
        ),
      ),
      switchTheme: clay
          ? SwitchThemeData(
              thumbColor: WidgetStateProperty.all(Colors.white),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.accent
                    : colors.cork,
              ),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            )
          : null,
      sliderTheme: clay
          ? SliderThemeData(
              trackHeight: 12,
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.cork,
              thumbColor: Colors.white,
              overlayColor: colors.accent.withOpacity(0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 6),
              trackShape: const RoundedRectSliderTrackShape(),
            )
          : null,
      progressIndicatorTheme: clay
          ? ProgressIndicatorThemeData(
              color: colors.accent,
              linearTrackColor: colors.cork,
              circularTrackColor: colors.cork,
              linearMinHeight: 12,
            )
          : null,
      useMaterial3: true,
    );
  }
}
