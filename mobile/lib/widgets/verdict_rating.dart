import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// Default verdict captions for a 1–10 heart rating — warm and specific
/// rather than a bare number, so the rating reads as a reaction rather
/// than a score. Used by [VerdictRating] whenever a theme doesn't
/// supply its own set (the coach and garden flows can pass their own
/// ten lines to match their own language).
const List<String> kDefaultVerdictLabels = [
  'not the one',
  'rough sit',
  "glad that's over",
  'just okay',
  'decent watch',
  'genuinely liked it',
  'really good',
  'loved every minute',
  'one for the shelf',
  'perfect show',
];

/// The rating moment itself, dressed to feel like it's happening right
/// there in the seat instead of being filled out on a form afterwards:
/// bigger hearts sitting inside a soft, breathing spotlight, each tap
/// landing with a small settle, and a live one-line verdict underneath
/// that changes together with the rating — so picking a number reads
/// as reacting to the film, not filing a score.
class VerdictRating extends StatefulWidget {
  final int value; // 0-max
  final int max;
  final ValueChanged<int> onChanged;
  final Animation<double>? breathe; // shared pulse from the parent screen; runs its own if omitted
  final List<String> labels; // exactly `max` entries, low to high
  final String idleLabel;
  final double heartSize;

  const VerdictRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 10,
    this.breathe,
    this.labels = kDefaultVerdictLabels,
    this.idleLabel = 'tap a heart to rate it',
    this.heartSize = 25,
  });

  @override
  State<VerdictRating> createState() => _VerdictRatingState();
}

class _VerdictRatingState extends State<VerdictRating> with SingleTickerProviderStateMixin {
  late final AnimationController _own;
  int? _justLanded;

  @override
  void initState() {
    super.initState();
    if (widget.breathe == null) {
      _own = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    } else {
      _own = AnimationController(vsync: this, duration: const Duration(milliseconds: 1));
    }
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  Animation<double> get _pulse => widget.breathe ?? _own;

  void _tap(int i) {
    final next = i == widget.value ? 0 : i;
    HapticFeedback.selectionClick();
    setState(() => _justLanded = next == 0 ? null : next);
    widget.onChanged(next);
    if (next != 0) {
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted && _justLanded == next) setState(() => _justLanded = null);
      });
    }
  }

  String get _caption {
    final v = widget.value;
    if (v <= 0) return widget.idleLabel;
    final idx = ((v - 1) * widget.labels.length / widget.max).floor().clamp(0, widget.labels.length - 1);
    return widget.labels[idx];
  }

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.ratingColor(widget.value > 0 ? widget.value : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.heartSize + 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // A slow, soft wash of color behind the hearts — the same
              // breathing rhythm as the screen glow elsewhere in the
              // ritual, so the rating feels lit rather than printed.
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final t = 0.35 + 0.65 * ((math.sin(_pulse.value * 2 * math.pi) + 1) / 2);
                  return Container(
                    width: 240,
                    height: widget.heartSize + 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: RadialGradient(
                        colors: [color.withOpacity(0.20 * t), color.withOpacity(0)],
                      ),
                    ),
                  );
                },
              ),
              // The hearts themselves — always exactly one row. A plain
              // Wrap used to sit here, but at ten hearts plus their
              // padding it was often just wide enough to spill a
              // couple onto a second line, which read as broken rather
              // than deliberate. Measuring the available width and
              // shrinking the hearts (never the row itself) keeps the
              // whole scale on one line on every card width and every
              // theme, small screens included.
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 3.0;
                  const perHeartPadding = 4.0; // _VerdictHeart's own 2px+2px padding
                  final totalSpacing = spacing * (widget.max - 1);
                  final fitted = ((constraints.maxWidth - totalSpacing) / widget.max) - perHeartPadding;
                  final heartSize = fitted.clamp(14.0, widget.heartSize);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 1; i <= widget.max; i++) ...[
                        if (i > 1) const SizedBox(width: spacing),
                        _VerdictHeart(
                          filled: i <= widget.value,
                          color: color,
                          justLanded: _justLanded == i,
                          size: heartSize,
                          onTap: () => _tap(i),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            widget.value > 0 ? '$_caption · ${widget.value}/${widget.max}' : _caption,
            key: ValueKey(_caption),
            style: SeenlyText.serif(italic: true, size: 13.5, color: color),
          ),
        ),
      ],
    );
  }
}

class _VerdictHeart extends StatelessWidget {
  final bool filled;
  final Color color;
  final bool justLanded;
  final double size;
  final VoidCallback onTap;

  const _VerdictHeart({
    required this.filled,
    required this.color,
    required this.justLanded,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: justLanded ? 1.32 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            filled ? Icons.favorite : Icons.favorite_border,
            size: size,
            color: filled ? color : SeenlyPalette.dashedBorder,
          ),
        ),
      ),
    );
  }
}
