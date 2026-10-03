import 'package:flutter/material.dart';

import '../theme/clay_kit.dart';
import '../theme/palette.dart';
import '../theme/seenly_skin.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart' show Entrance, BreathingGlow;

/// A shared, more considered empty-state layout — meant to replace the
/// "one line of italic placeholder text floating in the middle of the
/// screen" pattern repeated across the app (Collections, Search, Diary,
/// the co-viewing hub, ...) with something that actually looks designed:
/// a soft icon badge (optionally with a slow breathing glow behind it —
/// see [glow]), a title, an optional quieter caption underneath, and an
/// optional action below that. Settles in with [Entrance] rather than
/// just snapping into place.
///
/// Deliberately simple and config-driven (icon + one or two strings +
/// one optional action) so any screen can pick this up without bespoke
/// layout work — see plan_evening_sheet.dart's partner-not-linked state
/// for a first call site. For a shelf/grid-shaped empty state (posters,
/// tickets, ...) reach for [GhostPosterRow] instead of an icon badge —
/// see plan_evening_sheet.dart's plan-to-watch shelf for that one.
class SeenlyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? caption;
  final Widget? action;
  final bool glow;
  final Color? iconColor;
  final EdgeInsets padding;

  const SeenlyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    this.action,
    this.glow = false,
    this.iconColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 28),
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? SeenlyPalette.accent;
    if (SeenlySkin.isClay) {
      return Entrance(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClayBlobFace(size: 92, color: iconColor ?? SeenlyPalette.pink, badge: icon),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: SeenlyText.emptyState(size: 15)),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.placeholder),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      );
    }
    Widget badge = Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.32), width: 1.2),
      ),
      child: Icon(icon, size: 25, color: color.withOpacity(0.85)),
    );
    if (glow) {
      badge = BreathingGlow(color: color, size: 76, child: badge);
    }
    return Entrance(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge,
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: SeenlyText.emptyState(size: 14)),
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(
                caption!,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.placeholder),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Three faint, slightly tilted "ghost" poster rectangles — a wordless
/// hint that this empty space is a shelf, and that posters will sit
/// right here once something lands on it, rather than a paragraph
/// explaining that. Purely decorative: no shared tilt/parallax math with
/// the real grid (see mosaic_poster_grid.dart) — this is deliberately
/// looser and simpler since nothing here is ever tapped.
class GhostPosterRow extends StatelessWidget {
  final IconData centerIcon;
  const GhostPosterRow({super.key, this.centerIcon = Icons.local_movies_outlined});

  @override
  Widget build(BuildContext context) {
    Widget tile({required double angle, bool center = false}) => Transform.rotate(
          angle: angle,
          child: Container(
            width: center ? 58 : 50,
            height: center ? 87 : 75,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: SeenlyPalette.paper.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.3),
            ),
            child: center
                ? Icon(centerIcon, size: 20, color: SeenlyPalette.inkFaint)
                : null,
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tile(angle: -0.11),
        tile(angle: 0, center: true),
        tile(angle: 0.11),
      ],
    );
  }
}
