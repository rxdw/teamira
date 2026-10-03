import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'seenly_brightness.dart';
import 'seenly_skin.dart';
import 'text_styles.dart';

// =============================================================================
// CLAY KIT — the actual claymorphism / kawaii design system.
//
// The old "clay" skin was only a palette + a font + one extra drop shadow, so
// it looked like the standard skin painted lavender. Real claymorphism has a
// specific anatomy, and this file implements every part of it:
//
//   1. a fat, squircle-ish radius (nothing is ever sharp),
//   2. an OUTER soft drop shadow (tinted, not grey) + a light bounce on the
//      top-left, so the object reads as lifted off the page,
//   3. an INNER highlight (top-left) and an INNER shade (bottom-right) — this
//      is the part that makes a surface look like puffed-up plasticine and
//      not like a flat card with a shadow. Flutter's BoxShadow can't be inset,
//      so [ClayBoxDecoration] paints it itself,
//   4. squishy, springy interaction (press = the object is pushed in),
//   5. kawaii: pastel candy colours, little faces, hearts/stars/clouds.
//
// Everything here is inert outside the clay skin — [ClayBoxDecoration] paints
// exactly like a plain [BoxDecoration] unless [SeenlySkin.isClay] is on, so the
// classic and cozy skins are untouched.
// =============================================================================

/// Colour helpers for deriving a clay object's highlight / shade from its own
/// base colour (so a mint blob gets a deeper mint shade, not a grey one).
class ClayTones {
  const ClayTones._();

  static Color lighten(Color c, double amount) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amount).clamp(0.0, 1.0).toDouble()).toColor();
  }

  /// A deeper, slightly more saturated sibling of [c] — the "shade" side of a
  /// puffy surface.
  static Color shadeOf(Color c, [double amount = 0.16]) {
    final h = HSLColor.fromColor(c);
    return h
        .withLightness((h.lightness - amount).clamp(0.0, 1.0).toDouble())
        .withSaturation((h.saturation + 0.10).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  /// Readable label colour for text sitting on a clay object of colour [bg].
  static Color onColor(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : SeenlyPalette.ink;
  }
}

/// The outer shadow stacks for raised / pressed clay.
class ClayShadows {
  const ClayShadows._();

  /// [elevation] 1.0 = a normal card, ~0.5 = a small chip, 0.25 = pressed in.
  /// [tint] lets a coloured object (an accent button) cast a glow in its own
  /// colour instead of the neutral rose-brown shadow.
  static List<BoxShadow> raised({Color? tint, double elevation = 1.0}) {
    final dark = SeenlyBrightness.isDark;
    final e = elevation;
    final base = tint ?? SeenlyPalette.shadowColor;
    return [
      BoxShadow(
        color: base.withOpacity(tint != null ? 0.40 : (dark ? 0.42 : 0.26)),
        blurRadius: 26 * e,
        offset: Offset(0, 12 * e),
        spreadRadius: -3 * e,
      ),
      BoxShadow(
        color: base.withOpacity(dark ? 0.30 : 0.13),
        blurRadius: 7 * e,
        offset: Offset(0, 3 * e),
      ),
      if (!dark)
        BoxShadow(
          color: Colors.white.withOpacity(0.95),
          blurRadius: 16 * e,
          offset: Offset(-6 * e, -6 * e),
        ),
    ];
  }
}

/// Paints the two inner shadows that turn a flat rounded rectangle into a
/// puffed-up clay object: a light one hugging the top-left inner edge and a
/// tinted dark one hugging the bottom-right. [inset] flips the light source —
/// used for wells / pressed-in trays, where the surface dips *into* the page.
void paintClayInnerShading(
  Canvas canvas,
  RRect rrect, {
  required Color base,
  double depth = 1.0,
  bool inset = false,
}) {
  final shortest = math.min(rrect.width, rrect.height);
  if (shortest < 14) return;
  final k = depth.clamp(0.5, 2.0).toDouble();
  final blur = (shortest * 0.17).clamp(6.0, 15.0).toDouble();
  final d = blur * 0.62 * k;
  final dark = SeenlyBrightness.isDark;

  final hiColor = dark ? Colors.white.withOpacity(0.13) : Colors.white.withOpacity(0.92);
  final shColor = dark
      ? Colors.black.withOpacity(0.34)
      : ClayTones.shadeOf(base).withOpacity((0.55 * k).clamp(0.0, 0.85).toDouble());

  canvas.save();
  canvas.clipRRect(rrect);
  if (inset) {
    _innerLayer(canvas, rrect, Offset(d, d), shColor, blur);
    _innerLayer(canvas, rrect, Offset(-d, -d), hiColor, blur);
  } else {
    _innerLayer(canvas, rrect, Offset(-d, -d), shColor, blur);
    _innerLayer(canvas, rrect, Offset(d, d), hiColor, blur);
  }
  canvas.restore();
}

void _innerLayer(Canvas canvas, RRect rrect, Offset shift, Color color, double blur) {
  final outer = rrect.outerRect.inflate(blur * 3 + shift.distance + 4);
  final path = Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(outer)
    ..addRRect(rrect.shift(shift));
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
  );
}

/// A drop-in [BoxDecoration] that, in the clay skin only, also paints the inner
/// highlight/shade. Every constructor argument is the same as [BoxDecoration]'s,
/// so existing card code only needs its class name swapped.
class ClayBoxDecoration extends BoxDecoration {
  const ClayBoxDecoration({
    super.color,
    super.image,
    super.border,
    super.borderRadius,
    super.boxShadow,
    super.gradient,
    super.backgroundBlendMode,
    super.shape,
    this.clayDepth = 1.0,
    this.clayInset = false,
    this.clayBase,
    this.clayForce = false,
  });

  /// Paint the inner shading even when the clay skin isn't the active one —
  /// for skin *previews* (onboarding / settings) that must show clay while
  /// another skin is live.
  final bool clayForce;

  /// 1.0 = normal puffiness; >1 deeper (a pressed button), <1 subtler.
  final double clayDepth;

  /// True for wells / trays that dip into the page instead of rising from it.
  final bool clayInset;

  /// The colour the shading is derived from when [color] is null (gradient
  /// surfaces).
  final Color? clayBase;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _ClayBoxPainter(super.createBoxPainter(onChanged), this);
  }

  @override
  bool operator ==(Object other) {
    return super == other &&
        other is ClayBoxDecoration &&
        other.clayDepth == clayDepth &&
        other.clayInset == clayInset &&
        other.clayBase == clayBase &&
        other.clayForce == clayForce;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, clayDepth, clayInset, clayBase, clayForce);
}

class _ClayBoxPainter extends BoxPainter {
  _ClayBoxPainter(this._base, this._decoration) : super(_base.onChanged);

  final BoxPainter _base;
  final ClayBoxDecoration _decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    _base.paint(canvas, offset, configuration);
    final size = configuration.size;
    final d = _decoration;
    if (size == null || size.isEmpty || !(SeenlySkin.isClay || d.clayForce)) return;
    final fill = d.clayBase ?? d.color;
    if (fill == null && d.gradient == null) return;
    if (fill != null && fill.opacity < 0.55) return;

    final rect = offset & size;
    final RRect rrect;
    if (d.shape == BoxShape.circle) {
      final r = rect.shortestSide / 2;
      rrect = RRect.fromRectAndRadius(
        Rect.fromCircle(center: rect.center, radius: r),
        Radius.circular(r),
      );
    } else {
      final br = d.borderRadius?.resolve(configuration.textDirection) ?? BorderRadius.zero;
      rrect = br.toRRect(rect);
      if (math.max(rrect.tlRadiusX, rrect.brRadiusX) < 8) return;
    }
    paintClayInnerShading(
      canvas,
      rrect,
      base: fill ?? SeenlyPalette.paper,
      depth: d.clayDepth,
      inset: d.clayInset,
    );
  }

  @override
  void dispose() {
    _base.dispose();
    super.dispose();
  }
}

/// A dented "well" decoration for text fields / search boxes: the surface dips
/// into the page (inner shade top-left, light bounce bottom-right), and gains a
/// bubblegum ring while focused.
ClayBoxDecoration clayWellDecoration({bool focused = false, double radius = 26}) {
  return ClayBoxDecoration(
    color: SeenlyPalette.cork,
    clayInset: true,
    borderRadius: BorderRadius.circular(radius),
    border: focused ? Border.all(color: SeenlyPalette.accent.withOpacity(0.7), width: 2.2) : null,
  );
}

// -----------------------------------------------------------------------------
// ClaySurface — a puffy container.
// -----------------------------------------------------------------------------
class ClaySurface extends StatelessWidget {
  final Widget? child;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool circle;
  final double depth;
  final double elevation;
  final bool inset;
  final bool clip;
  final Color? glow;

  const ClaySurface({
    super.key,
    this.child,
    this.radius = 28,
    this.color,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.circle = false,
    this.depth = 1.0,
    this.elevation = 1.0,
    this.inset = false,
    this.clip = false,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? SeenlyPalette.paper;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: inset
          ? [ClayTones.shadeOf(base, 0.03), base, ClayTones.lighten(base, 0.02)]
          : [ClayTones.lighten(base, 0.035), base, ClayTones.shadeOf(base, 0.035)],
      stops: const [0.0, 0.5, 1.0],
    );
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: ClayBoxDecoration(
        gradient: gradient,
        clayBase: base,
        clayDepth: depth,
        clayInset: inset,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        boxShadow: inset ? const [] : ClayShadows.raised(tint: glow, elevation: elevation),
      ),
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// ClayButton — the squishy CTA. Press = the object is physically pushed in:
// it shrinks, its drop shadow collapses and its inner shading deepens.
// -----------------------------------------------------------------------------
class ClayButton extends StatefulWidget {
  final String? label;
  final Widget? child;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final Color? foreground;
  final bool expand;
  final bool loading;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const ClayButton({
    super.key,
    this.label,
    this.child,
    this.icon,
    this.onTap,
    this.color,
    this.foreground,
    this.expand = true,
    this.loading = false,
    this.radius = 26,
    this.padding = const EdgeInsets.symmetric(vertical: 15, horizontal: 26),
    this.fontSize = 15,
  });

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final base = widget.color ?? SeenlyPalette.accent;
    final fg = widget.foreground ??
        (widget.color == null ? SeenlyPalette.accentOnAccent : ClayTones.onColor(base));
    final dim = widget.onTap == null && !widget.loading;

    final content = widget.child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: widget.fontSize + 5, color: fg),
              const SizedBox(width: 8),
            ],
            if (widget.label != null)
              Flexible(
                child: Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: widget.fontSize, weight: FontWeight.w800, color: fg),
                ),
              ),
          ],
        );

    final button = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _pressed ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final lift = 1.0 - 0.72 * t;
        return Transform.scale(
          scale: 1.0 - 0.045 * t,
          child: Opacity(
            opacity: dim ? 0.55 : 1.0,
            child: Container(
              padding: widget.padding,
              alignment: Alignment.center,
              decoration: ClayBoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    ClayTones.lighten(base, 0.05),
                    base,
                    ClayTones.shadeOf(base, 0.05),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                clayBase: base,
                clayDepth: 1.0 + 0.6 * t,
                borderRadius: BorderRadius.circular(widget.radius),
                boxShadow: ClayShadows.raised(tint: base, elevation: 0.62 * lift + 0.08),
              ),
              child: child,
            ),
          ),
        );
      },
      child: widget.loading
          ? SizedBox(
              height: widget.fontSize + 4,
              child: Center(child: KawaiiFace(size: widget.fontSize + 4, color: fg, blush: false)),
            )
          : content,
    );

    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? widget.onTap : null,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: button,
    );
    return widget.expand ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

// -----------------------------------------------------------------------------
// ClayChip — small selectable pill.
// -----------------------------------------------------------------------------
class ClayChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool fullWidth;
  final VoidCallback? onTap;
  final Color? activeColor;

  const ClayChip({
    super.key,
    required this.label,
    this.active = false,
    this.fullWidth = false,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill = active ? (activeColor ?? SeenlyPalette.accent) : SeenlyPalette.paper;
    final fg = active ? ClayTones.onColor(fill) : SeenlyPalette.inkMuted;
    final chip = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: ClaySurface(
        key: ValueKey<bool>(active),
        radius: 20,
        color: fill,
        elevation: active ? 0.5 : 0.32,
        glow: active ? fill : null,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 12.5, weight: FontWeight.w800, color: fg),
        ),
      ),
    );
    final wrapped = fullWidth ? SizedBox(width: double.infinity, child: chip) : chip;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: wrapped);
  }
}

// -----------------------------------------------------------------------------
// ClayTabBar — segmented control: a dented tray with a raised, coloured pill
// popping up under the active label. Replaces the underline tabs in clay.
// -----------------------------------------------------------------------------
class ClayTabBar extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final bool allowScroll;
  final EdgeInsetsGeometry margin;

  const ClayTabBar({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.allowScroll = false,
    this.margin = EdgeInsets.zero,
  });

  static const double _pillPadX = 18;

  TextStyle _style(bool active) => SeenlyText.serif(
        size: 13.5,
        weight: FontWeight.w800,
        color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
      );

  Widget _pill(int i, {required bool expand}) {
    final active = i == activeIndex;
    final label = Text(
      labels[i],
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: _style(active),
    );
    final Widget body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1.0).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: active
          ? ClaySurface(
              key: const ValueKey<String>('on'),
              radius: 22,
              color: SeenlyPalette.accent,
              glow: SeenlyPalette.accent,
              elevation: 0.42,
              padding: const EdgeInsets.symmetric(horizontal: _pillPadX, vertical: 10),
              child: Center(child: label),
            )
          : Container(
              key: const ValueKey<String>('off'),
              padding: const EdgeInsets.symmetric(horizontal: _pillPadX, vertical: 10),
              color: Colors.transparent,
              child: Center(child: label),
            ),
    );
    final tap = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(i),
      child: body,
    );
    return expand ? Expanded(child: tap) : tap;
  }

  @override
  Widget build(BuildContext context) {
    Widget tray(Widget row) => Container(
          margin: margin,
          padding: const EdgeInsets.all(5),
          decoration: ClayBoxDecoration(
            color: SeenlyPalette.cork,
            clayInset: true,
            borderRadius: BorderRadius.circular(28),
          ),
          child: row,
        );

    if (!allowScroll) {
      return tray(Row(children: [for (var i = 0; i < labels.length; i++) _pill(i, expand: true)]));
    }
    return LayoutBuilder(builder: (context, constraints) {
      var need = 10.0;
      for (final l in labels) {
        need += (TextPainter(
          text: TextSpan(text: l, style: _style(true)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout())
                .width +
            _pillPadX * 2;
      }
      if (need <= constraints.maxWidth - 8) {
        return tray(Row(children: [for (var i = 0; i < labels.length; i++) _pill(i, expand: true)]));
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: tray(Row(children: [for (var i = 0; i < labels.length; i++) _pill(i, expand: false)])),
      );
    });
  }
}

// -----------------------------------------------------------------------------
// KawaiiFace — two shiny eyes, rosy cheeks and a tiny smile.
// -----------------------------------------------------------------------------
enum KawaiiMood { happy, sleepy, wow }

class KawaiiFace extends StatelessWidget {
  final double size;
  final KawaiiMood mood;
  final Color? color;
  final bool blush;

  const KawaiiFace({
    super.key,
    this.size = 40,
    this.mood = KawaiiMood.happy,
    this.color,
    this.blush = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.72,
      child: CustomPaint(
        painter: _KawaiiFacePainter(
          mood: mood,
          ink: color ?? SeenlyPalette.ink,
          cheek: SeenlyPalette.pink,
          blush: blush,
        ),
      ),
    );
  }
}

class _KawaiiFacePainter extends CustomPainter {
  final KawaiiMood mood;
  final Color ink;
  final Color cheek;
  final bool blush;
  const _KawaiiFacePainter({
    required this.mood,
    required this.ink,
    required this.cheek,
    required this.blush,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final eyeY = h * 0.38;
    final eyeDx = w * 0.27;
    final cx = w / 2;

    final fill = Paint()..color = ink;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, w * 0.05);

    if (blush) {
      final b = Paint()..color = cheek.withOpacity(0.55);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx - w * 0.40, h * 0.62), width: w * 0.20, height: h * 0.20), b);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + w * 0.40, h * 0.62), width: w * 0.20, height: h * 0.20), b);
    }

    for (final sx in [-1.0, 1.0]) {
      final c = Offset(cx + sx * eyeDx, eyeY);
      if (mood == KawaiiMood.sleepy) {
        final p = Path()
          ..moveTo(c.dx - w * 0.08, c.dy)
          ..quadraticBezierTo(c.dx, c.dy + h * 0.16, c.dx + w * 0.08, c.dy);
        canvas.drawPath(p, line);
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.13, height: h * 0.25), fill);
        canvas.drawCircle(
            Offset(c.dx - w * 0.02, c.dy - h * 0.06), w * 0.028, Paint()..color = Colors.white);
      }
    }

    final my = h * 0.66;
    if (mood == KawaiiMood.wow) {
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, my), width: w * 0.09, height: h * 0.17), fill);
    } else {
      final m = Path()
        ..moveTo(cx - w * 0.09, my - h * 0.02)
        ..quadraticBezierTo(cx - w * 0.045, my + h * 0.14, cx, my - h * 0.01)
        ..quadraticBezierTo(cx + w * 0.045, my + h * 0.14, cx + w * 0.09, my - h * 0.02);
      canvas.drawPath(m, line);
    }
  }

  @override
  bool shouldRepaint(covariant _KawaiiFacePainter old) =>
      old.mood != mood || old.ink != ink || old.cheek != cheek || old.blush != blush;
}

/// A round clay blob with a kawaii face — the mascot-ish thing empty states
/// and loaders wear.
class ClayBlobFace extends StatelessWidget {
  final double size;
  final Color? color;
  final KawaiiMood mood;
  final IconData? badge;

  const ClayBlobFace({
    super.key,
    this.size = 84,
    this.color,
    this.mood = KawaiiMood.happy,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? SeenlyPalette.pink;
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClaySurface(
            width: size,
            height: size,
            radius: size * 0.42,
            color: ClayTones.lighten(base, 0.12),
            elevation: size / 110,
            glow: base,
            child: Center(
              child: KawaiiFace(size: size * 0.58, mood: mood, color: ClayTones.shadeOf(base, 0.42)),
            ),
          ),
          if (badge != null)
            Positioned(
              right: 0,
              top: 0,
              child: ClaySurface(
                width: size * 0.36,
                height: size * 0.36,
                circle: true,
                color: SeenlyPalette.paper,
                elevation: 0.3,
                child: Icon(badge, size: size * 0.2, color: base),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ClayLoader — a little clay blob that hops, squashes and stretches while it
// waits. The app's spinner in the clay skin.
// -----------------------------------------------------------------------------
class ClayLoader extends StatefulWidget {
  final double size;
  const ClayLoader({super.key, this.size = 42});

  @override
  State<ClayLoader> createState() => _ClayLoaderState();
}

class _ClayLoaderState extends State<ClayLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = widget.size * 0.72;
    final colors = [SeenlyPalette.pink, SeenlyPalette.sage, SeenlyPalette.mustard, SeenlyPalette.periwinkle];
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // 0..1 hop: up on the first 55%, down + squash on the rest.
          final up = t < 0.55 ? Curves.easeOut.transform(t / 0.55) : 1 - Curves.easeIn.transform((t - 0.55) / 0.45);
          final landing = t < 0.55 ? 0.0 : math.sin((t - 0.55) / 0.45 * math.pi);
          final sx = 1.0 - 0.10 * up + 0.16 * landing;
          final sy = 1.0 + 0.14 * up - 0.16 * landing;
          final color = colors[(_c.lastElapsedDuration?.inMilliseconds ?? 0) ~/ 1100 % colors.length];
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: blob * (0.7 + 0.25 * (1 - up)),
                height: blob * 0.14,
                decoration: BoxDecoration(
                  color: SeenlyPalette.shadowColor.withOpacity(0.16 * (1 - up * 0.6)),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: widget.size * 0.14 * up + widget.size * 0.04),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(sx, sy, 1.0),
                  child: ClaySurface(
                    width: blob,
                    height: blob * 0.9,
                    radius: blob * 0.4,
                    color: ClayTones.lighten(color, 0.10),
                    elevation: 0.35,
                    glow: color,
                    child: Center(
                      child: KawaiiFace(
                        size: blob * 0.6,
                        mood: landing > 0.3 ? KawaiiMood.wow : KawaiiMood.happy,
                        color: ClayTones.shadeOf(color, 0.42),
                        blush: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ClayBackdrop — the soft pastel world behind everything: a milky gradient,
// big airy colour clouds, and a scatter of tiny drifting hearts / sparkles /
// clouds / flowers. Cheap on purpose: gradients instead of blurs.
// -----------------------------------------------------------------------------
class ClayBackdrop extends StatefulWidget {
  const ClayBackdrop({super.key});

  @override
  State<ClayBackdrop> createState() => _ClayBackdropState();
}

class _ClayBackdropState extends State<ClayBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
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
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ClayBackdropPainter(_c),
      ),
    );
  }
}

class _Doodle {
  final double x, y, size, phase, speed;
  final int kind, tone;
  const _Doodle(this.x, this.y, this.size, this.kind, this.tone, this.phase, this.speed);
}

class _ClayBackdropPainter extends CustomPainter {
  final Animation<double> t;
  _ClayBackdropPainter(this.t) : super(repaint: t);

  // kind: 0 heart, 1 sparkle, 2 cloud, 3 flower, 4 ring, 5 dot
  static const _doodles = <_Doodle>[
    _Doodle(0.08, 0.07, 13, 1, 1, 0.0, 1),
    _Doodle(0.90, 0.05, 15, 0, 0, 1.3, 1),
    _Doodle(0.80, 0.16, 30, 2, 3, 2.1, 1),
    _Doodle(0.05, 0.24, 24, 3, 0, 3.4, 1),
    _Doodle(0.94, 0.31, 11, 1, 2, 0.7, 2),
    _Doodle(0.10, 0.42, 12, 4, 3, 4.2, 1),
    _Doodle(0.91, 0.49, 20, 3, 1, 5.0, 1),
    _Doodle(0.06, 0.58, 17, 0, 4, 2.6, 2),
    _Doodle(0.88, 0.64, 34, 2, 0, 1.9, 1),
    _Doodle(0.12, 0.72, 12, 1, 0, 3.0, 1),
    _Doodle(0.93, 0.78, 12, 5, 2, 0.4, 2),
    _Doodle(0.07, 0.86, 26, 2, 2, 4.6, 1),
    _Doodle(0.86, 0.90, 16, 0, 1, 5.5, 1),
    _Doodle(0.50, 0.03, 9, 5, 3, 1.1, 2),
    _Doodle(0.42, 0.95, 12, 1, 3, 2.9, 1),
  ];

  List<Color> get _tones => [
        SeenlyPalette.pink,
        SeenlyPalette.mustard,
        SeenlyPalette.sage,
        SeenlyPalette.periwinkle,
        SeenlyPalette.coral,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final dark = SeenlyBrightness.isDark;
    final bg = SeenlyPalette.background;
    final rect = Offset.zero & size;

    // Milky vertical gradient — ends on the exact background colour so the
    // floating nav dock's flat strip below it matches seamlessly.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ClayTones.lighten(bg, dark ? 0.03 : 0.035), bg],
        ).createShader(rect),
    );

    // Airy colour clouds.
    void cloud(double fx, double fy, double fr, Color c, double a) {
      final centre = Offset(size.width * fx, size.height * fy);
      final r = size.width * fr;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withOpacity(a), c.withOpacity(0)],
          ).createShader(Rect.fromCircle(center: centre, radius: r)),
      );
    }

    final tones = _tones;
    final a = dark ? 0.14 : 0.30;
    final drift = t.value * 2 * math.pi;
    cloud(0.05 + 0.02 * math.sin(drift), 0.10, 0.62, tones[0], a);
    cloud(0.98, 0.42 + 0.02 * math.cos(drift), 0.55, tones[3], a * 0.9);
    cloud(0.10, 0.80 + 0.015 * math.sin(drift + 1), 0.6, tones[2], a * 0.9);
    cloud(0.95, 0.98, 0.5, tones[1], a * 0.8);

    final da = dark ? 0.30 : 0.62;
    for (final d in _doodles) {
      final wob = math.sin(drift * d.speed + d.phase);
      final wob2 = math.cos(drift * d.speed * 0.8 + d.phase);
      final c = Offset(size.width * d.x + wob2 * 3.5, size.height * d.y + wob * 6);
      final color = tones[d.tone % tones.length].withOpacity(da);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(wob * 0.18);
      switch (d.kind) {
        case 0:
          _heart(canvas, d.size, color);
          break;
        case 1:
          _sparkle(canvas, d.size, color);
          break;
        case 2:
          _cloudShape(canvas, d.size, color.withOpacity(da * 0.8));
          break;
        case 3:
          _flower(canvas, d.size, color);
          break;
        case 4:
          canvas.drawCircle(
            Offset.zero,
            d.size * 0.5,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6,
          );
          break;
        default:
          canvas.drawCircle(Offset.zero, d.size * 0.4, Paint()..color = color);
      }
      canvas.restore();
    }
  }

  void _heart(Canvas canvas, double s, Color color) {
    final r = s * 0.5;
    final path = Path()..moveTo(0, r * 0.82);
    path
      ..cubicTo(-r * 1.35, -r * 0.05, -r * 0.72, -r, 0, -r * 0.38)
      ..cubicTo(r * 0.72, -r, r * 1.35, -r * 0.05, 0, r * 0.82)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _sparkle(Canvas canvas, double s, Color color) {
    final r = s * 0.55;
    final p = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..quadraticBezierTo(0, 0, 0, r)
      ..quadraticBezierTo(0, 0, -r, 0)
      ..quadraticBezierTo(0, 0, 0, -r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _cloudShape(Canvas canvas, double s, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(-s * 0.28, 0), s * 0.26, p);
    canvas.drawCircle(Offset(0, -s * 0.14), s * 0.34, p);
    canvas.drawCircle(Offset(s * 0.30, 0), s * 0.24, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, s * 0.1), width: s * 0.9, height: s * 0.3),
        Radius.circular(s * 0.15),
      ),
      p,
    );
  }

  void _flower(Canvas canvas, double s, Color color) {
    final p = Paint()..color = color;
    for (var i = 0; i < 5; i++) {
      final ang = i * 2 * math.pi / 5 - math.pi / 2;
      canvas.drawCircle(Offset(math.cos(ang), math.sin(ang)) * (s * 0.3), s * 0.2, p);
    }
    canvas.drawCircle(Offset.zero, s * 0.14, Paint()..color = SeenlyPalette.mustard.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(covariant _ClayBackdropPainter old) => false;
}
