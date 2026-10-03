// How a widget's class name becomes an analytics screen name.
//
// Kept free of Flutter imports so it can be unit-tested with plain
// `dart test` (see test/analytics/screen_names_test.dart), and because it
// is THE rule that mobile/tools/analytics/list_screens.py mirrors: a screen
// is any widget class whose name ends in `Screen`, a sheet any that ends in
// `Sheet`, and a leading underscore is dropped. If you change this rule,
// change that script the same way — the "never opened" section of
// backend/scripts/analytics_report.py is only right while the two agree.
//
// One caveat worth knowing: this reads `runtimeType.toString()`, which is
// the class name only in normal builds. `flutter build --obfuscate` renames
// classes, and every screen would then be reported under its obfuscated
// name. If you turn obfuscation on, give routes explicit
// `RouteSettings(name: ...)` — the observer prefers those.

class AnalyticsScreenName {
  /// e.g. `TitleDetailScreen`, `PlanEveningSheet` — no leading underscore.
  final String name;

  /// `screen` or `sheet`.
  final String kind;

  const AnalyticsScreenName(this.name, this.kind);

  @override
  String toString() => '$kind:$name';
}

final RegExp _screenTypePattern = RegExp(r'^_?([A-Z][A-Za-z0-9]*(Screen|Sheet))$');

// Flutter's own widgets that end in "Sheet" and sit *above* the app's
// content inside a bottom-sheet route. Without this the observer would name
// every sheet "BottomSheet", because that framework wrapper is found first
// on the way down the tree.
final RegExp _frameworkWidgetPattern = RegExp(r'BottomSheet|DraggableScrollableSheet|ActionSheet');

/// The analytics name for a widget type, or null if it isn't one of ours.
AnalyticsScreenName? screenNameFromTypeName(String typeName) {
  final m = _screenTypePattern.firstMatch(typeName);
  if (m == null) return null;
  final name = m.group(1)!;
  if (_frameworkWidgetPattern.hasMatch(name)) return null;
  return AnalyticsScreenName(name, m.group(2) == 'Sheet' ? 'sheet' : 'screen');
}
