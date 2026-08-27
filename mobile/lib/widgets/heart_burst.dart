import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';

/// Wraps a favorite icon (or any child) and plays a small, satisfying
/// burst of hearts the instant [isFavorite] flips from false to true —
/// a lighter, everyday cousin of the achievement-unlock and level-up
/// "wow" moments elsewhere in the app (see achievement_unlock_overlay.dart,
/// level_up_celebration.dart). Those two stop the whole screen for
/// something rare; favoriting happens all the time, so this is a
/// half-second flourish layered right on the button itself instead —
/// no overlay, no dialog, nothing that could stack up if someone taps a
/// few hearts in a row.
///
/// Purely decorative: this widget doesn't call any toggle logic itself,
/// doesn't know why [isFavorite] changed, and never un-favorites
/// anything — it only ever reacts, never drives. Drop it around an
/// existing favorite icon/button wherever one lives; the button keeps
/// its own tap handling exactly as before.
class HeartBurst extends StatefulWidget {
  final bool isFavorite;
  final Widget child;
  final Color? color;

  const HeartBurst({
    super.key,
    required this.isFavorite,
    required this.child,
    this.color,
  });

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  // Fixed layout, seeded once — a burst that reshuffled every rebuild
  // would look jittery rather than lively.
  late final List<_Particle> _particles = _makeParticles();

  List<_Particle> _makeParticles() {
    const count = 7;
    final rnd = math.Random(7);
    return List.generate(count, (i) {
      final angle = (i / count) * 2 * math.pi + rnd.nextDouble() * 0.5;
      final distance = 20.0 + rnd.nextDouble() * 16;
      final size = 6.0 + rnd.nextDouble() * 6;
      final delay = rnd.nextDouble() * 0.18;
      return _Particle(angle: angle, distance: distance, size: size, delay: delay);
    });
  }

  @override
  void didUpdateWidget(covariant HeartBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isFavorite && widget.isFavorite) {
      HapticFeedback.lightImpact();
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SeenlyPalette.pink;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.value == 0 || _c.value == 1) return const SizedBox.shrink();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final p in _particles) _particle(p, color),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _particle(_Particle p, Color color) {
    final local = ((_c.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();
    final eased = Curves.easeOutCubic.transform(local);
    final dx = math.cos(p.angle) * p.distance * eased;
    // A touch of upward drift on top of the radial spread — closer to
    // how a real handful of confetti hearts would fall/float than a
    // perfectly even burst.
    final dy = math.sin(p.angle) * p.distance * eased - (8 * eased);
    final opacity = 1 - Curves.easeIn.transform(local);
    final scale = 0.4 + (1 - local) * 0.6;

    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Icon(Icons.favorite, size: p.size, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double distance;
  final double size;
  final double delay;
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
  });
}
