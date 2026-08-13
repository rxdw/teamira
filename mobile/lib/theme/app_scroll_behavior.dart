import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One consistent scroll feel for the whole app, instead of whatever
/// each platform's default happens to be.
///
/// Out of the box, Flutter's [MaterialScrollBehavior] gives iOS a soft
/// rubber-band [BouncingScrollPhysics] at the edges and gives Android /
/// Fuchsia a [ClampingScrollPhysics] that refuses to move past the edge
/// at all, painted over instead with a grey/black [GlowingOverscrollIndicator]
/// smear. That's two different "end of the shelf" feelings living side
/// by side in an app whose whole visual language is warm paper and soft,
/// deliberate motion — the Android glow in particular reads like a stock
/// Material widget dropped straight into a handmade page, and it shows
/// up on *every* shelf at once (diary polaroids, "for you, with
/// trailers", the collection/genre carousels, ...) since none of them
/// set their own physics.
///
/// This makes the choice once, for every scrollable in the app:
/// [BouncingScrollPhysics] everywhere (same overscroll feel regardless
/// of platform) and no overscroll indicator at all (the bounce already
/// gives its own feedback, so the indicator this would otherwise paint
/// on Android/Fuchsia is both redundant and off-palette). See
/// `app.dart`, where this is wired in via `MaterialApp.scrollBehavior`.
class SeenlyScrollBehavior extends MaterialScrollBehavior {
  const SeenlyScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // The iOS-style rubber band, on every platform — see class doc.
    return const BouncingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No glow anywhere — BouncingScrollPhysics above already gives every
    // scrollable its own edge feedback.
    return child;
  }
}
