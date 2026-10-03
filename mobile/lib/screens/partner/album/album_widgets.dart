import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pair_album.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'album_strings.dart';

/// The pair album's shared visual vocabulary: things that drift (sparks),
/// things that seal (wax, envelopes), things that are written on (note
/// paper), and one celebration (confetti). Every screen in this folder is
/// built from these, so the whole feature reads as one object — a small
/// book the two of you keep — rather than five unrelated screens.
///
/// Everything here is paint + transforms: no images, no extra packages.
/// Animations respect the platform's "reduce motion" setting through
/// [albumReduceMotion], falling back to the finished frame.

/// True when the person asked the OS to cut down on motion. Ambient loops
/// (drifting sparks, breathing) stop; one-shot reveals jump to their end
/// state instead of playing.
bool albumReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ---------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------

Path albumHeartPath(Offset c, double size) {
  final w = size;
  final h = size;
  final path = Path()
    ..moveTo(c.dx, c.dy + h * 0.38)
    ..cubicTo(c.dx - w * 0.85, c.dy - h * 0.10, c.dx - w * 0.42, c.dy - h * 0.78, c.dx, c.dy - h * 0.30)
    ..cubicTo(c.dx + w * 0.42, c.dy - h * 0.78, c.dx + w * 0.85, c.dy - h * 0.10, c.dx, c.dy + h * 0.38)
    ..close();
  return path;
}

Path albumStarPath(Offset c, double r) {
  final path = Path();
  const points = 4;
  for (var i = 0; i < points * 2; i++) {
    final radius = i.isEven ? r : r * 0.34;
    final angle = -math.pi / 2 + i * math.pi / points;
    final p = Offset(c.dx + radius * math.cos(angle), c.dy + radius * math.sin(angle));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// Drifting sparks — the ambient background of the emotional screens
// ---------------------------------------------------------------------------

class AlbumSparks extends StatefulWidget {
  final Color color;
  final int count;
  final double opacity;
  const AlbumSparks({
    super.key,
    required this.color,
    this.count = 16,
    this.opacity = 0.55,
  });

  @override
  State<AlbumSparks> createState() => _AlbumSparksState();
}

class _SparkSeed {
  final double x;
  final double speed;
  final double size;
  final double phase;
  final double sway;
  final bool heart;
  const _SparkSeed(this.x, this.speed, this.size, this.phase, this.sway, this.heart);
}

class _AlbumSparksState extends State<AlbumSparks> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late final List<_SparkSeed> _seeds;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _seeds = List.generate(widget.count, (i) {
      return _SparkSeed(
        rnd.nextDouble(),
        0.6 + rnd.nextDouble() * 0.9,
        5 + rnd.nextDouble() * 9,
        rnd.nextDouble(),
        6 + rnd.nextDouble() * 16,
        i % 3 != 0,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (albumReduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: _SparksPainter(_seeds, _c.value, widget.color, widget.opacity),
          ),
        ),
      ),
    );
  }
}

class _SparksPainter extends CustomPainter {
  final List<_SparkSeed> seeds;
  final double t;
  final Color color;
  final double opacity;
  _SparksPainter(this.seeds, this.t, this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in seeds) {
      // Each spark rises once per loop at its own speed, offset by its phase.
      final progress = ((t * s.speed) + s.phase) % 1.0;
      final y = size.height * (1.08 - progress * 1.2);
      final x = size.width * s.x + math.sin((progress + s.phase) * math.pi * 2) * s.sway;
      // Fade in at the bottom, out at the top.
      final fade = math.sin(progress * math.pi).clamp(0.0, 1.0);
      final paint = Paint()..color = color.withOpacity(opacity * fade * 0.6);
      final c = Offset(x, y);
      canvas.drawPath(s.heart ? albumHeartPath(c, s.size) : albumStarPath(c, s.size * 0.7), paint);
    }
  }

  @override
  bool shouldRepaint(_SparksPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Wax seal
// ---------------------------------------------------------------------------

class WaxSeal extends StatelessWidget {
  final double size;
  final Color? color;
  final IconData icon;
  const WaxSeal({super.key, this.size = 44, this.color, this.icon = Icons.favorite_rounded});

  @override
  Widget build(BuildContext context) {
    final base = color ?? SeenlyPalette.coral;
    final dark = Color.lerp(base, Colors.black, 0.28)!;
    final light = Color.lerp(base, Colors.white, 0.28)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [light, base, dark],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: dark.withOpacity(0.38),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.66,
        height: size * 0.66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.36, color: Colors.white.withOpacity(0.92)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

/// An envelope that opens as [progress] goes 0 → 1: the flap swings up,
/// the letter (whatever [letter] is) rises out. Driven from outside so the
/// same widget serves the note reveal and the capsule ceremony — and so a
/// reduced-motion caller can simply pass 1.
class EnvelopeView extends StatelessWidget {
  final double progress;
  final double width;
  final Widget? letter;
  final Color? color;
  final Color? sealColor;
  const EnvelopeView({
    super.key,
    required this.progress,
    this.width = 280,
    this.letter,
    this.color,
    this.sealColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    final body = color ?? SeenlyPalette.paper;
    final shade = Color.lerp(body, SeenlyPalette.ink, 0.10)!;
    final bodyH = width * 0.66;
    final flapH = bodyH * 0.58;
    // cos maps 0 → 1 (closed, flap hangs over the front), 0.5 → 0 (edge on),
    // 1 → -1 (open, flap stands up behind the letter).
    final flapScale = math.cos(p * math.pi);
    final letterT = Curves.easeOutCubic.transform(((p - 0.45) / 0.55).clamp(0.0, 1.0).toDouble());
    final rise = letterT * bodyH * 0.62;
    final total = bodyH + flapH;

    return SizedBox(
      width: width,
      height: total,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: flapH,
            height: bodyH,
            child: CustomPaint(painter: _EnvelopeBackPainter(shade)),
          ),
          if (flapScale < 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: flapH + 1,
              child: CustomPaint(
                painter: _FlapPainter(
                  shade: Color.lerp(shade, SeenlyPalette.ink, 0.06)!,
                  scaleY: flapScale,
                  anchorFromTop: false,
                ),
              ),
            ),
          if (letter != null)
            Positioned(
              left: width * 0.07,
              right: width * 0.07,
              top: flapH + bodyH * 0.05 - rise,
              height: bodyH * 0.95,
              child: letter!,
            ),
          Positioned(
            left: 0,
            right: 0,
            top: flapH,
            height: bodyH,
            child: CustomPaint(painter: _EnvelopeFrontPainter(body, shade)),
          ),
          if (flapScale >= 0)
            Positioned(
              left: 0,
              right: 0,
              top: flapH,
              height: flapH * math.max(flapScale, 0.001),
              child: CustomPaint(
                painter: _FlapPainter(
                  shade: body,
                  scaleY: 1,
                  anchorFromTop: true,
                  outline: shade,
                ),
              ),
            ),
          if (flapScale > 0.25)
            Positioned(
              left: width / 2 - 22,
              top: flapH + flapH * flapScale - 22,
              child: Opacity(
                opacity: ((flapScale - 0.25) / 0.75).clamp(0.0, 1.0).toDouble(),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * flapScale,
                  child: WaxSeal(size: 44, color: sealColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EnvelopeBackPainter extends CustomPainter {
  final Color color;
  _EnvelopeBackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawShadow(Path()..addRRect(r), Colors.black.withOpacity(0.5), 8, false);
    canvas.drawRRect(r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EnvelopeBackPainter old) => old.color != color;
}

class _EnvelopeFrontPainter extends CustomPainter {
  final Color body;
  final Color shade;
  _EnvelopeFrontPainter(this.body, this.shade);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.52, h * 0.58)
      ..lineTo(0, h)
      ..close();
    final right = Path()
      ..moveTo(w, 0)
      ..lineTo(w * 0.48, h * 0.58)
      ..lineTo(w, h)
      ..close();
    final bottom = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.5, h * 0.44)
      ..lineTo(w, h)
      ..close();
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    canvas.drawPath(left, Paint()..color = Color.lerp(body, shade, 0.55)!);
    canvas.drawPath(right, Paint()..color = Color.lerp(body, shade, 0.55)!);
    canvas.drawPath(bottom, Paint()..color = body);
    final line = Paint()
      ..color = shade.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(bottom, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EnvelopeFrontPainter old) => old.body != body || old.shade != shade;
}

class _FlapPainter extends CustomPainter {
  final Color shade;
  final double scaleY;
  final bool anchorFromTop;
  final Color? outline;
  _FlapPainter({
    required this.shade,
    required this.scaleY,
    required this.anchorFromTop,
    this.outline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (anchorFromTop) {
      // Hangs from the top edge of the body, apex pointing down.
      path
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w / 2, h)
        ..close();
    } else {
      // Open: stands up above the body, apex pointing up, base on the
      // bottom edge of this box (which is the body's top edge).
      path
        ..moveTo(0, h)
        ..lineTo(w, h)
        ..lineTo(w / 2, h - h * (-scaleY))
        ..close();
    }
    canvas.drawPath(path, Paint()..color = shade);
    if (outline != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = outline!.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_FlapPainter old) => old.scaleY != scaleY || old.shade != shade;
}

// ---------------------------------------------------------------------------
// Note paper
// ---------------------------------------------------------------------------

/// A handwritten-looking sticky note: paper, a strip of tape, ruled lines,
/// a hair of tilt. [body] is the text; [byline] the "от …" line; [mood] the
/// author's tag; [reaction] the other person's reply, pinned to the corner.
class NotePaper extends StatelessWidget {
  final String body;
  final String? byline;
  final String? mood;
  final String? reaction;
  final Color? tint;
  final double tilt;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  const NotePaper({
    super.key,
    required this.body,
    this.byline,
    this.mood,
    this.reaction,
    this.tint,
    this.tilt = 0,
    this.fontSize = 18,
    this.padding = const EdgeInsets.fromLTRB(18, 20, 18, 16),
  });

  @override
  Widget build(BuildContext context) {
    final base = tint ?? SeenlyPalette.mustard;
    final paper = Color.lerp(SeenlyPalette.paper, base, 0.16)!;
    return Transform.rotate(
      angle: tilt,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: SeenlyPalette.shadowColor.withOpacity(0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _RulesPainter(base.withOpacity(0.22), fontSize * 1.42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (byline != null) ...[
                    Text(byline!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    body,
                    style: SeenlyText.handwrittenNote(size: fontSize, color: SeenlyPalette.ink)
                        .copyWith(height: 1.42),
                  ),
                  if (mood != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(mood!, style: const TextStyle(fontSize: 22)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Transform.rotate(
                angle: -0.04,
                child: Container(
                  width: 58,
                  height: 16,
                  decoration: BoxDecoration(
                    color: base.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          if (reaction != null)
            Positioned(
              right: -6,
              bottom: -10,
              child: Entrance(
                duration: const Duration(milliseconds: 480),
                riseBy: 8,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SeenlyPalette.shadowColor.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(reaction!, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesPainter extends CustomPainter {
  final Color color;
  final double step;
  _RulesPainter(this.color, this.step);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    // Start below the byline so lines sit under the text, not through it.
    for (var y = step + 8; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RulesPainter old) => old.color != color || old.step != step;
}

/// What a note looks like while it's sealed from the reader — same paper,
/// no words, a wax seal in the middle. Never given any text at all.
class SealedNotePaper extends StatelessWidget {
  final String label;
  final Color? tint;
  final double tilt;
  const SealedNotePaper({super.key, required this.label, this.tint, this.tilt = 0});

  @override
  Widget build(BuildContext context) {
    final base = tint ?? SeenlyPalette.periwinkle;
    final paper = Color.lerp(SeenlyPalette.paper, base, 0.14)!;
    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: SeenlyPalette.shadowColor.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            BreathingGlow(
              color: SeenlyPalette.coral,
              size: 54,
              child: const WaxSeal(size: 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: SeenlyText.handwrittenNote(size: 16, color: SeenlyPalette.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// A row of tappable emoji — the mood picker and the reaction bar. Selecting
/// the current one again clears it (unless [allowClear] is false).
class EmojiChoiceRow extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final double size;
  final bool allowClear;
  const EmojiChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.size = 24,
    this.allowClear = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              if (selected == e && allowClear) {
                onChanged(null);
              } else {
                onChanged(e);
              }
            },
            child: AnimatedScale(
              scale: selected == e ? 1.16 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size + 20,
                height: size + 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected == e
                      ? SeenlyPalette.accent.withOpacity(0.16)
                      : SeenlyPalette.ink.withOpacity(0.05),
                  border: Border.all(
                    color: selected == e ? SeenlyPalette.accent : Colors.transparent,
                    width: 1.6,
                  ),
                ),
                child: Text(e, style: TextStyle(fontSize: size)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A poster with a soft paper fallback — the album never needs the themed
/// tile's frames, just a small honest picture of the title.
class AlbumPoster extends StatelessWidget {
  final String? url;
  final double width;
  final double radius;
  final Color? fallback;
  const AlbumPoster({
    super.key,
    required this.url,
    this.width = 56,
    this.radius = 8,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final color = fallback ?? SeenlyPalette.accent;
    final hasUrl = url != null && url!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: width * 1.5,
        color: color.withOpacity(0.16),
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.movie_outlined, color: color, size: width * 0.4),
              )
            : Icon(Icons.movie_outlined, color: color, size: width * 0.4),
      ),
    );
  }
}

/// Two avatars side by side with a heart between them.
class PairAvatars extends StatelessWidget {
  final List<AlbumPerson> people;
  final double size;
  const PairAvatars({super.key, required this.people, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final two = people.length >= 2 ? people.sublist(0, 2) : people;
    final children = <Widget>[];
    for (var i = 0; i < two.length; i++) {
      final p = two[i];
      children.add(
        UserAvatar(
          avatarUrl: p.avatarUrl,
          avatarPreset: p.avatarPreset,
          fallbackLetter: p.letter,
          size: size,
          borderColor: SeenlyPalette.paper,
        ),
      );
      if (i == 0 && two.length > 1) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.16),
            child: BreathingGlow(
              color: SeenlyPalette.coral,
              size: size * 0.7,
              child: Icon(Icons.favorite_rounded, color: SeenlyPalette.coral, size: size * 0.34),
            ),
          ),
        );
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

/// The album's bottom-sheet chrome: paper background, rounded top, a grab
/// handle, and room for the keyboard. Returns whatever the sheet pops with.
Future<T?> showAlbumSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: SeenlyPalette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: SeenlyPalette.inkFaint.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: builder(sheetContext)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

/// One burst of hearts and paper bits that falls and fades — played once
/// when the widget appears. Put it in a Stack over the screen; it ignores
/// touches. Under reduced motion it renders nothing.
class AlbumConfetti extends StatefulWidget {
  final List<Color>? colors;
  final int count;
  final Duration duration;
  const AlbumConfetti({
    super.key,
    this.colors,
    this.count = 46,
    this.duration = const Duration(milliseconds: 3200),
  });

  @override
  State<AlbumConfetti> createState() => _AlbumConfettiState();
}

class _Bit {
  final double angle;
  final double speed;
  final double size;
  final double spin;
  final int colorIndex;
  final bool heart;
  const _Bit(this.angle, this.speed, this.size, this.spin, this.colorIndex, this.heart);
}

class _AlbumConfettiState extends State<AlbumConfetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final List<_Bit> _bits;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(11);
    _bits = List.generate(widget.count, (i) {
      return _Bit(
        -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.15,
        0.55 + rnd.nextDouble() * 0.75,
        6 + rnd.nextDouble() * 8,
        (rnd.nextDouble() - 0.5) * 9,
        i,
        i % 2 == 0,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!albumReduceMotion(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (albumReduceMotion(context)) return const SizedBox.shrink();
    final palette = widget.colors ??
        [
          SeenlyPalette.coral,
          SeenlyPalette.pink,
          SeenlyPalette.mustard,
          SeenlyPalette.accent,
          SeenlyPalette.periwinkle,
        ];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_bits, palette, _c.value),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final List<Color> palette;
  final double t;
  _ConfettiPainter(this.bits, this.palette, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.42);
    final reach = size.shortestSide * 0.9;
    for (final b in bits) {
      // Ballistic: out fast, then gravity pulls it down.
      final travel = Curves.easeOutCubic.transform(t) * reach * b.speed;
      final x = origin.dx + math.cos(b.angle) * travel;
      final y = origin.dy + math.sin(b.angle) * travel + math.pow(t, 2.2) * size.height * 0.55;
      final fade = (1 - ((t - 0.55) / 0.45)).clamp(0.0, 1.0).toDouble();
      final paint = Paint()..color = palette[b.colorIndex % palette.length].withOpacity(fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * t);
      if (b.heart) {
        canvas.drawPath(albumHeartPath(Offset.zero, b.size), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.5),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Shared little labels
// ---------------------------------------------------------------------------

/// "от насти" / "от вас" style byline.
String albumByline({required bool mine, required String name}) =>
    mine ? at('ваша записка', 'your note') : at('от $name', 'from $name');
