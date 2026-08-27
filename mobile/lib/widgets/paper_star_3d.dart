import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';

/// A small faceted paper-star ornament, genuinely modeled and lit in 3D
/// — not a sprite, not a flat icon rotated to fake depth. It's the same
/// trick a three.js hero on a marketing site plays (real vertices, a
/// rotation matrix, a light direction, faces shaded by their own
/// normal), just done by hand with [CustomPainter] instead of a WebGL
/// context, since that's all ten spinning triangles need.
///
/// Shape: a ten-point bipyramid — two apexes (top/bottom) joined to a
/// ring of ten equator vertices that alternate between an outer and an
/// inner radius, the same construction as a folded-paper star ornament
/// (long spike, short valley, long spike, ...). 20 triangular facets
/// total, each one a flat plane the way real folded paper would be —
/// no smooth shading, on purpose, so it keeps reading as *paper*
/// rather than a glossy render.
///
/// Spins on its own (slow, ambient) and can be grabbed and turned by a
/// finger, the same "alive, and yours to touch" spirit as the onboarding
/// orbit hero it sits alongside — drag left/right to spin it, up/down to
/// tip it, let go and it keeps drifting from wherever you left it rather
/// than snapping back to a fixed pose.
class PaperStar3D extends StatefulWidget {
  final double size;

  const PaperStar3D({super.key, this.size = 120});

  @override
  State<PaperStar3D> createState() => _PaperStar3DState();
}

class _PaperStar3DState extends State<PaperStar3D> with SingleTickerProviderStateMixin {
  // One continuously-repeating controller drives every frame of motion
  // here — the idle spin directly, and (via its listener) the pitch's
  // slow ease back to level whenever a finger isn't actively tipping
  // it. A single ticker for both keeps the two motions perfectly in
  // step with each other instead of running on separate clocks.
  late final AnimationController _ticker =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..addListener(_onTick)
        ..repeat();

  // Manual spin nudged in by a drag — added on *top* of the idle spin
  // below rather than replacing it, so grabbing the star gives it a
  // push rather than pausing its ambient rotation. Never reset; a drag
  // permanently reorients where "idle" currently points.
  double _dragYaw = 0;

  // Tip (rotation around the horizontal axis) is drag-only and always
  // eases back toward level when nothing's touching it — see
  // [_onTick] — so it reads as "gently tipped, then settles" rather
  // than staying cocked at whatever angle a finger last left it.
  double _pitch = 0;
  bool _dragging = false;

  double get _yaw => _ticker.value * 2 * math.pi + _dragYaw;

  void _onTick() {
    if (_dragging) return;
    // Exponential ease toward level. 0.06/frame at 60fps settles in
    // well under a second — quick enough that it doesn't look like it
    // forgot to return, slow enough that it still reads as a soft
    // settle rather than a snap.
    if (_pitch.abs() > 0.001) setState(() => _pitch *= 0.94);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    setState(() => _dragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _dragYaw += d.delta.dx * 0.012;
      _pitch = (_pitch + d.delta.dy * 0.012).clamp(-0.6, 0.6);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    // A flick keeps spinning it a little further on its own — carried
    // by the drag's release velocity rather than stopping dead the
    // instant the finger lifts.
    final flick = (d.velocity.pixelsPerSecond.dx / 900).clamp(-2.5, 2.5);
    setState(() {
      _dragYaw += flick * 0.3;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) {
            return CustomPaint(
              painter: _PaperStarPainter(yaw: _yaw, pitch: _pitch),
            );
          },
        ),
      ),
    );
  }
}

class _Vec3 {
  final double x, y, z;
  const _Vec3(this.x, this.y, this.z);

  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);

  _Vec3 cross(_Vec3 o) =>
      _Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;

  _Vec3 get normalized {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len < 1e-9) return this;
    return _Vec3(x / len, y / len, z / len);
  }

  /// Rotated by yaw around the vertical (Y) axis, then by pitch around
  /// the horizontal (X) axis — applied in that order every time so a
  /// drag's yaw and pitch compose the same way frame to frame instead
  /// of the star's tilt axis itself drifting as it spins.
  _Vec3 rotated(double yaw, double pitch) {
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final rx = x * cy + z * sy;
    final rz = -x * sy + z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final ry = y * cp - rz * sp;
    final rz2 = y * sp + rz * cp;
    return _Vec3(rx, ry, rz2);
  }
}

class _Face {
  final int a, b, c;
  // A little variance per facet — alternating warm tones so the star
  // reads as folded from a few different paper scraps rather than one
  // flat-colored solid, the same washi-tape-mix instinct as the app's
  // tapeRose/tapeSage/tapeMustard palette elsewhere.
  final Color base;
  const _Face(this.a, this.b, this.c, this.base);
}

class _PaperStarPainter extends CustomPainter {
  final double yaw;
  final double pitch;
  _PaperStarPainter({required this.yaw, required this.pitch});

  // Geometry is built fresh per paint (cheap — 12 verts, 20 faces) so
  // the painter stays a pure function of (yaw, pitch) with nothing to
  // keep in sync.
  static const _outer = 1.0;
  static const _inner = 0.42;
  static const _halfHeight = 0.62;
  static const _points = 5;

  List<_Vec3> _vertices() {
    final verts = <_Vec3>[
      const _Vec3(0, -_halfHeight, 0), // 0: top apex
      const _Vec3(0, _halfHeight, 0), // 1: bottom apex
    ];
    for (int i = 0; i < _points * 2; i++) {
      final angle = i * math.pi / _points;
      final r = i.isEven ? _outer : _inner;
      verts.add(_Vec3(math.cos(angle) * r, 0, math.sin(angle) * r));
    }
    return verts;
  }

  List<_Face> _faces() {
    final faces = <_Face>[];
    const equatorStart = 2;
    const n = _points * 2;
    for (int i = 0; i < n; i++) {
      final a = equatorStart + i;
      final b = equatorStart + (i + 1) % n;
      // Alternate two warm tones per spike so neighbouring facets read
      // as distinct folded panels rather than one continuous surface.
      final tint = i.isEven ? SeenlyPalette.mustard : SeenlyPalette.coral;
      faces.add(_Face(0, a, b, tint)); // top cap
      faces.add(_Face(1, b, a, tint)); // bottom cap (reversed winding)
    }
    return faces;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 0.8, not something closer to 1.0: the near-side vertices scale
    // up under perspective (see `project` below), so leaving this
    // margin keeps the star's tips from clipping the canvas edge at
    // the angles where a spike swings closest to the camera.
    final scaleBase = math.min(size.width, size.height) / 2 * 0.8;
    const cameraDist = 3.2; // in the same units as _outer/_inner/_halfHeight
    final lightDir = const _Vec3(-0.45, -0.55, 0.7).normalized;

    final verts = _vertices().map((v) => v.rotated(yaw, pitch)).toList();
    final faces = _faces();

    // Painter's algorithm: farthest facets first so nearer ones paint
    // over them. Not a true z-buffer, but this shape is close enough
    // to convex that per-face average depth gives a clean result at
    // any angle it's likely to be viewed from.
    final ordered = [...faces]..sort((f1, f2) {
        final z1 = (verts[f1.a].z + verts[f1.b].z + verts[f1.c].z) / 3;
        final z2 = (verts[f2.a].z + verts[f2.b].z + verts[f2.c].z) / 3;
        return z1.compareTo(z2);
      });

    Offset project(_Vec3 v) {
      final s = cameraDist / (cameraDist - v.z);
      return center + Offset(v.x * s * scaleBase, -v.y * s * scaleBase);
    }

    final crease = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;

    for (final f in ordered) {
      final va = verts[f.a], vb = verts[f.b], vc = verts[f.c];
      // Outward normal from the rotated triangle itself — recomputed
      // per frame rather than rotating a precomputed normal, so it's
      // never at risk of drifting out of sync with the vertices.
      final normal = (vb - va).cross(vc - va).normalized;
      if (normal.z <= 0) continue; // facing away from camera — skip

      final intensity = normal.dot(lightDir).clamp(0.0, 1.0);
      const ambient = 0.38;
      final lit = ambient + (1 - ambient) * intensity;
      final color = Color.lerp(
        Color.lerp(f.base, Colors.black, 0.28)!,
        Color.lerp(f.base, Colors.white, 0.55)!,
        lit,
      )!;

      final path = Path()
        ..moveTo(project(va).dx, project(va).dy)
        ..lineTo(project(vb).dx, project(vb).dy)
        ..lineTo(project(vc).dx, project(vc).dy)
        ..close();

      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, crease..color = Color.lerp(color, Colors.black, 0.35)!);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperStarPainter oldDelegate) =>
      oldDelegate.yaw != yaw || oldDelegate.pitch != pitch;
}
