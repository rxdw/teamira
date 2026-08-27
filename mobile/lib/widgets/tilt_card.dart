import 'package:flutter/material.dart';

/// A gesture-driven 3D tilt — the same "the card leans into the light as
/// your pointer moves across it" trick a lot of marketing sites reach
/// for with a WebGL/three.js scene, done here with a plain perspective
/// [Transform] and a pointer-following glare instead of a 3D engine.
///
/// Wrap any card-shaped widget (already carrying its own decoration,
/// shadow, clipping) in [TiltCard]. While a finger is down on it, the
/// card leans away from the touch point — up to [maxAngle] radians on
/// both axes — and (if [glare] is on) a soft highlight slides across
/// toward the finger, the way light would catch glossy card stock. On
/// release both spring back to resting flat with a small overshoot
/// rather than snapping, so it reads as something physical settling
/// back down rather than a value resetting.
///
/// Deliberately built on a raw [Listener] rather than a
/// [GestureDetector]'s pan recognizer: this needs *every* pointer move
/// while a finger is down, not just the ones a drag recognizer decides
/// to award it, and it should never compete in the gesture arena with
/// an ancestor's own drag (e.g. a swipe-to-dismiss wrapped around this
/// same card) — both should get to react to the same touch.
class TiltCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  /// Radians of rotation at the very edge of the card. ~9° (the
  /// default) reads as lively without tipping into cartoonish.
  final double maxAngle;

  /// A soft highlight that slides toward the pointer as it moves —
  /// off by default for anything dark enough that a white glare would
  /// wash out the art (turn on for posters/photos, leave off for flat
  /// color chips or text-heavy cards).
  final bool glare;

  const TiltCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.maxAngle = 0.16,
    this.glare = true,
  });

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> with SingleTickerProviderStateMixin {
  final GlobalKey _boxKey = GlobalKey();
  late final AnimationController _release = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  // Normalized pointer position, -1 (top/left edge) .. 1 (bottom/right
  // edge), 0 dead center. Driven directly off the pointer while a
  // finger is down; the moment it lifts, [_release] eases the last
  // value it held (frozen into [_releasedFrom]) back down to zero.
  Offset _pointer = Offset.zero;
  Offset _releasedFrom = Offset.zero;
  bool _down = false;

  @override
  void dispose() {
    _release.dispose();
    super.dispose();
  }

  void _updateFromGlobal(Offset globalPosition) {
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return;
    final local = box.globalToLocal(globalPosition);
    final nx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _pointer = Offset(nx, ny));
  }

  void _onDown(PointerDownEvent e) {
    _down = true;
    _release.stop();
    _updateFromGlobal(e.position);
  }

  void _onMove(PointerMoveEvent e) {
    if (_down) _updateFromGlobal(e.position);
  }

  void _onLift() {
    if (!_down) return;
    _down = false;
    _releasedFrom = _pointer;
    _release
      ..value = 0
      ..forward();
    setState(() => _pointer = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _boxKey,
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _onLift(),
      onPointerCancel: (_) => _onLift(),
      child: GestureDetector(
        // Tap alone (no drag) still fires normally — Listener above
        // sees the same raw events but never enters the gesture arena,
        // so it can't steal the tap.
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _release,
          builder: (context, child) {
            final t = _down
                ? _pointer
                : Offset.lerp(
                    _releasedFrom,
                    Offset.zero,
                    Curves.easeOutBack.transform(_release.value),
                  )!;
            final rotY = t.dx * widget.maxAngle;
            final rotX = -t.dy * widget.maxAngle;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // perspective: how far the "camera" sits
              ..rotateX(rotX)
              ..rotateY(rotY);
            return Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: widget.glare
                  ? ClipRRect(
                      borderRadius: widget.borderRadius,
                      // Deliberately the default StackFit.loose, not
                      // passthrough: this Stack can sit under an
                      // ancestor that hands down unbounded constraints
                      // (e.g. a Column with mainAxisSize.min, as in the
                      // poster lightbox) — passthrough would forward
                      // that straight to the glare's Align/
                      // FractionallySizedBox below, which can't resolve
                      // a size against infinity and throws. Loose fit
                      // sizes the Stack off [child]'s own explicit
                      // size (the card always has one), and
                      // Positioned.fill below then gets a concrete,
                      // finite size to work with regardless of what the
                      // Stack itself was given.
                      child: Stack(
                        children: [
                          child!,
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: t.distance.clamp(0.0, 1.0) * 0.32,
                                child: Align(
                                  alignment: Alignment(t.dx, t.dy),
                                  child: FractionallySizedBox(
                                    widthFactor: 1.7,
                                    heightFactor: 1.7,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: RadialGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.95),
                                            Colors.white.withOpacity(0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : child!,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
