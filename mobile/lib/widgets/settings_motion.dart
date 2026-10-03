import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'soft_motion.dart';
import 'wow_motion.dart' show Entrance, PressScale;

/// The small kit the settings-and-account screens share, so that a dozen
/// screens of rows, toggles and buttons all move the same way: a page of
/// sections that settles in from the top, choices that fade to their
/// selected look instead of flipping, tap targets that dip under the
/// finger, and — elsewhere — waits that show three dots rather than a
/// spinner (see `BouncingDots`, and `PrimaryButton`'s loading state).

/// Wraps each child of a column of sections so that they settle in one
/// after another, top to bottom. Spacers (`SizedBox`, `Spacer`) are left
/// alone. Only the first [maxSteps] sections get a longer delay, so a very
/// long page doesn't spend seconds assembling itself — everything past
/// that arrives together with the last of them.
///
/// Don't use it on the children of a column that has `Expanded` /
/// `Flexible` children: wrapping those would break their layout.
List<Widget> staggerChildren(
  List<Widget> children, {
  Duration step = const Duration(milliseconds: 55),
  int maxSteps = 9,
}) {
  var n = 0;
  final out = <Widget>[];
  for (final child in children) {
    if (child is SizedBox || child is Spacer) {
      out.add(child);
      continue;
    }
    final i = n < maxSteps ? n : maxSteps;
    n++;
    out.add(Entrance(
      delay: step * i,
      duration: const Duration(milliseconds: 440),
      riseBy: 12,
      child: child,
    ));
  }
  return out;
}

/// A selectable swatch with a caption under it (the theme / skin / map-style
/// pickers): picking one fades its outline to the accent and thickens it,
/// with a soft glow; the caption firms up; the press dips. [child] is what's
/// drawn inside the swatch — give it a `key` if it changes with [selected]
/// and should cross-fade.
class OptionSwatch extends StatelessWidget {
  final Widget? child;
  final Color? fill;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const OptionSwatch({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.child,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    const fade = Duration(milliseconds: 240);
    return PressScale(
      onTap: onTap,
      scaleTo: 0.94,
      child: Column(
        children: [
          AnimatedContainer(
            duration: fade,
            curve: Curves.easeOutCubic,
            height: 40,
            decoration: BoxDecoration(
              color: fill ?? SeenlyPalette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: SeenlyPalette.accent.withOpacity(0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            alignment: Alignment.center,
            child: child,
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: fade,
            style: SeenlyText.mono(
              size: 9,
              color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

/// One small choice among several (a privacy level, a status): fades its
/// fill and text colour when it becomes the selected one. [onTap] null makes
/// it inert (while a change is saving).
class SoftChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double fontSize;

  const SoftChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fontSize = 9.5,
  });

  @override
  Widget build(BuildContext context) {
    const fade = Duration(milliseconds: 220);
    return PressScale(
      onTap: onTap,
      scaleTo: 0.93,
      child: AnimatedContainer(
        duration: fade,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedDefaultTextStyle(
          duration: fade,
          style: SeenlyText.mono(
            size: fontSize,
            weight: FontWeight.w700,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Swaps a screen's loading picture for its content with a soft cross-fade
/// instead of a cut. Pass the loaded/loading flag as [loaded] and both
/// pictures as builders-free widgets.
class LoadSwap extends StatelessWidget {
  final bool loaded;
  final Widget loading;
  final Widget content;

  const LoadSwap({super.key, required this.loaded, required this.loading, required this.content});

  @override
  Widget build(BuildContext context) {
    return SoftSwap(
      expand: true,
      alignment: Alignment.topCenter,
      rise: 0.015,
      duration: const Duration(milliseconds: 280),
      child: KeyedSubtree(
        key: ValueKey<bool>(loaded),
        child: loaded ? content : loading,
      ),
    );
  }
}

/// An icon whose colour fades to a new one when it changes (an option
/// becoming selected), instead of switching in a single frame.
class FadeIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const FadeIcon({super.key, required this.icon, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 240),
      builder: (context, c, _) => Icon(icon, size: size, color: c),
    );
  }
}
