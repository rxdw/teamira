import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import 'light_bloom.dart';

/// The one piece of atmosphere every screen sits on top of.
///
/// Until now the "little cinema" / "evening coach" / "window-box garden"
/// mood only ever showed up in two places: the logging ritual and the
/// diary's centerpiece. Everywhere else — search, a title page, lists,
/// Together, settings — sat on flat paper. [AmbientStage] takes the exact
/// same building blocks that already carry that mood ([LightMote] /
/// [DustPainter], the plum/mustard/sage that already mean "cinema" /
/// "coach" / "garden" everywhere else in the app) and plays them, very
/// quietly, behind *every* screen — so switching a theme in Settings
/// doesn't just re-skin a button, it re-tunes the whole app's light.
///
/// Deliberately restrained: this should read as "the room this app lives
/// in," not as another animation competing for attention. A screen using
/// this should look identical at a glance to one without it — the
/// difference is felt after a few seconds, not seen in a screenshot.
///
/// [seed] should be unique-ish per screen (a short constant name is
/// plenty) so the mote scatter is stable for that screen rather than
/// reshuffling on every rebuild; it never needs to change at runtime.
class AmbientStage extends StatefulWidget {
  final Widget child;
  final String seed;

  const AmbientStage({super.key, required this.child, required this.seed});

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;
  late final List<LightMote> _motes;

  @override
  void initState() {
    super.initState();
    // Fast enough to actually catch the eye within a few seconds, slow
    // enough that it never feels like it's asking to be watched.
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _motes = seededMotes(widget.seed, 16);
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  /// Where the current theme's quiet wash of color sits — a lamp above
  /// (ticket), a horizon below (coach), light through a window off to one
  /// side (garden). Matches the direction each theme's own ritual already
  /// implies, so the two never disagree.
  static const _glowAlign = {
    LogTheme.ticket: Alignment.topCenter,
    LogTheme.coach: Alignment(0, 1.1),
    LogTheme.garden: Alignment.topRight,
    LogTheme.shuttle: Alignment.topCenter,
  };

  static final _glowColor = {
    LogTheme.ticket: SeenlyPalette.accent,
    LogTheme.coach: SeenlyPalette.mustard,
    LogTheme.garden: SeenlyPalette.sage,
    LogTheme.shuttle: SeenlyPalette.periwinkle,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final align = _glowAlign[theme]!;
    final glow = _glowColor[theme]!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The paper itself, so every screen using this still has a solid
        // base even before anything else here paints.
        ColoredBox(color: SeenlyPalette.background),

        // A held wash of the chosen theme's color — soft, but a genuine
        // presence, not a whisper lost against the paper.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: align,
                radius: 1.3,
                colors: [glow.withOpacity(0.22), Colors.transparent],
              ),
            ),
          ),
        ),

        // A room vignette — corners settle noticeably darker, the way an
        // actual lamp-lit room does, rather than a flat lit stage.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.05,
                stops: [0.6, 1.0],
                colors: [Colors.transparent, Color(0x33000000)],
              ),
            ),
          ),
        ),

        // The same drifting light motes used by the logging rituals, now
        // tinted with the theme's own color rather than paper-on-paper —
        // on this light background, near-white dust would simply
        // disappear, so it's tinted to actually read.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              painter: DustPainter(t: _drift.value, motes: _motes, color: glow),
              size: Size.infinite,
            ),
          ),
        ),

        widget.child,
      ],
    );
  }
}
