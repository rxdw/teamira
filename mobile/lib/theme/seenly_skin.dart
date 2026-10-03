/// Which decorative skin [SeenlyPalette] should currently resolve to —
/// independent of light/dark (see seenly_brightness.dart) and
/// independent of [LogTheme] (services/log_theme_service.dart, which
/// only re-skins the logging ritual itself). This is the app-wide
/// "standard" vs "cozy diary" vs "clay" choice from Settings >
/// appearance > visual style:
///  - classic: the plain paper look
///  - cozy: a pastel, hand-drawn-paper look — scalloped awning banner,
///    washi tape, cork board
///  - clay: kawaii claymorphism — milky peach/strawberry pastels, fat
///    squircle radii, puffy surfaces with a real inner highlight + inner
///    shade and a tinted outer shadow (see theme/clay_kit.dart), a floating
///    dock nav, segmented clay tabs, kawaii faces in empty states/loaders,
///    a drifting hearts-and-sparkles backdrop, and Nunito (which, unlike the
///    old Fredoka/Quicksand pair, has Cyrillic) as the typeface
/// Each still respects whichever brightness is active, the same way
/// [SeenlyBrightness] does.
enum AppSkin { classic, cozy, clay }

/// Same "bare static flag" shape as [SeenlyBrightness], for the same
/// reason: [SeenlyPalette]'s color getters are read from places with no
/// `BuildContext` (CustomPainters, const-resolution helpers, other
/// static getters), so this needs to be ambient state rather than an
/// InheritedWidget.
///
/// Kept in sync with `AppSkinService` (see
/// services/app_skin_service.dart) — call [setSkin] whenever that
/// service's skin changes, before the dependent tree rebuilds.
class SeenlySkin {
  SeenlySkin._();

  static AppSkin _skin = AppSkin.classic;

  static void setSkin(AppSkin skin) {
    _skin = skin;
  }

  /// Whether [SeenlyPalette]'s ambient getters should currently hand
  /// back the cozy pastel variant.
  static bool get isCozy => _skin == AppSkin.cozy;

  /// Whether [SeenlyPalette]'s ambient getters should currently hand
  /// back the claymorphism variant.
  static bool get isClay => _skin == AppSkin.clay;
}
