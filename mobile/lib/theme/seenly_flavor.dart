/// Which premium color mood [SeenlyPalette] should currently resolve
/// to, on top of whichever [AppSkin] (classic/cozy) is active —
/// Settings > appearance's "апельсиновая"/"клубничная" options, sitting
/// in the same row as system/light/dark rather than as a separate
/// section (see [ThemePrefsService]'s [AppAppearance], which is the
/// single settings-facing choice this flag is derived from).
///
/// Deliberately NOT crossed with brightness the way [AppSkin] is: both
/// flavors are one fixed, always-light palette apiece (see
/// palette.dart's `_orangeClassic`/`_orangeCozy`/`_strawberryClassic`/
/// `_strawberryCozy`) rather than a light+dark pair. A "dark orange" or
/// "dark strawberry" would just be a muddy brown-maroon — it loses the
/// one thing a flavor is for — so [AppAppearance.themeMode] forces
/// `ThemeMode.light` whenever a flavor is chosen, and this flag is
/// simply ignored by [SeenlyPalette.darkColors] (nothing ever asks for
/// it while a flavor is active).
///
/// Still crossed with [AppSkin]: cozy's structural decoration (dot-grid
/// paper, washi tape, dog-ear corners — gated on `SeenlySkin.isCozy`
/// directly, not on color) stays exactly as it is under a flavor, it
/// just gets re-tinted, the same relationship classic/cozy already has
/// with light/dark.
enum AppFlavor { none, orange, strawberry }

/// Same "bare static flag" shape as [SeenlySkin]/`SeenlyBrightness`, for
/// the same reason — see those files' own doc comments on why this is
/// ambient state rather than an InheritedWidget. Kept in sync with
/// [ThemePrefsService] — call [setFlavor] whenever that service's
/// appearance changes, before the dependent tree rebuilds.
class SeenlyFlavor {
  SeenlyFlavor._();

  static AppFlavor _flavor = AppFlavor.none;

  static void setFlavor(AppFlavor flavor) {
    _flavor = flavor;
  }

  /// Whether [SeenlyPalette]'s ambient getters should currently hand
  /// back one of the flavor color sets instead of the neutral one.
  static AppFlavor get current => _flavor;
}
