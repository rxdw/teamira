import 'package:flutter/material.dart';

/// Seenly's own screen-to-screen transition — a fade paired with a soft
/// rise, echoing [Entrance]'s "settle in" language (see
/// `widgets/wow_motion.dart`), so pushing a new screen reads as the same
/// one voice as everything else in the app instead of falling back to
/// whatever the platform ships by default (Android's Material 3 zoom-
/// fade, which has nothing to do with the rest of Seenly's motion).
///
/// The page being covered doesn't just vanish either — it eases back a
/// couple of percent and fades a hair via [secondaryAnimation], so the
/// new screen reads as arriving *in front of* the old one rather than
/// the old one being hard-cut away.
///
/// Wired in for Android/desktop platforms only (see
/// `SeenlyAppTheme`'s `pageTransitionsTheme`) — iOS/macOS deliberately
/// keep [CupertinoPageTransitionsBuilder] instead, since that's the one
/// that ships the swipe-to-go-back edge gesture people on those
/// platforms expect. Losing that gesture for the sake of a matching
/// fade isn't a trade worth making, so the two platforms end up with
/// two different transitions on purpose — same as they already have two
/// different back gestures.
class SeenlyPageTransitionsBuilder extends PageTransitionsBuilder {
  const SeenlyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([incoming, outgoing]),
      child: child,
      builder: (context, child) {
        final inT = incoming.value;
        final outT = outgoing.value;
        return Opacity(
          // Fades in on the way in, and dips a little (never fully
          // transparent) while another screen is stacked on top of it.
          opacity: ((1 - outT * 0.35) * inT).clamp(0.0, 1.0),
          child: Transform.translate(
            // A rise, not a slide-from-the-side — matches Entrance's own
            // vocabulary rather than borrowing iOS's horizontal push.
            offset: Offset(0, (1 - inT) * 18),
            child: Transform.scale(
              // A couple of percent of recede while covered — just
              // enough to read as "behind", not a visible zoom.
              scale: 1 - outT * 0.02,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
