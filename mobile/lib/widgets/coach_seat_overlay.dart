import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/coach_routes.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart';
import '../services/app_translations.dart';

/// The "Evening Route" theme's counterpart to `seat_picker_overlay.dart`:
/// instead of a mini cinema, a coach idling at the stop, waiting for you
/// to settle into a seat before it pulls out. Same small, cozy pleasure
/// of choosing before the pass appears — nothing rides on which seat.
///
/// The coach's interior light "switches on" the same warm-bloom way the
/// cinema's lamp and the passport's desk light do, so all three rituals
/// read as one idea worn three ways. A small route plaque stands in for
/// the marquee/travel-tag, showing the real route tonight's runtime
/// matched to (see `coach_routes.dart`).
///
/// Call [showCoachSeat] rather than constructing this directly.
Future<void> showCoachSeat(
  BuildContext context, {
  required String title,
  required String mediaType,
  int? runtimeMinutes,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _CoachSeatOverlay(title: title, mediaType: mediaType, runtimeMinutes: runtimeMinutes),
      ),
    ),
  );
}

class _CoachSeatOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  final int? runtimeMinutes;

  const _CoachSeatOverlay({required this.title, required this.mediaType, required this.runtimeMinutes});

  @override
  State<_CoachSeatOverlay> createState() => _CoachSeatOverlayState();
}

class _CoachSeatOverlayState extends State<_CoachSeatOverlay> with TickerProviderStateMixin {
  static const int _rows = 4;
  static const int _cols = 4; // a coach's 2-and-2 layout, aisle down the middle

  late final AnimationController _appear;
  late final AnimationController _iris;
  late final AnimationController _flash;
  late final AnimationController _dust;
  late final AnimationController _breathe;
  late final List<LightMote> _motes;
  late final Set<int> _taken;
  late final CoachRoute _route;
  int? _selected;
  bool _popped = false;
  Timer? _advanceTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _route = routeForRuntime(
        runtimeMinutes: widget.runtimeMinutes, mediaType: widget.mediaType, seed: widget.title);
    _taken = _seededTaken(widget.title, _rows * _cols);
    _motes = seededMotes(widget.title, 9, salt: 0x636f6163); // 'coac'
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() => setState(() {}))
      ..forward();
    _iris = AnimationController(vsync: this, duration: const Duration(milliseconds: 720))
      ..addListener(() => setState(() {}))
      ..forward();
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..addListener(() => setState(() {}))
      ..forward();
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 7))
      ..addListener(() => setState(() {}))
      ..repeat();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))
      ..addListener(() => setState(() {}))
      ..repeat();
    _watchdog = Timer(const Duration(seconds: 20), _skip);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    _appear.dispose();
    _iris.dispose();
    _flash.dispose();
    _dust.dispose();
    _breathe.dispose();
    super.dispose();
  }

  static Set<int> _seededTaken(String seed, int total) {
    final r = math.Random(seed.hashCode ^ 0x636f6163);
    final count = 2 + r.nextInt(3);
    final taken = <int>{};
    while (taken.length < count && taken.length < total - 1) {
      taken.add(r.nextInt(total));
    }
    return taken;
  }

  void _choose(int index) {
    if (_selected != null || _taken.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 750), _popOnce);
  }

  void _skip() {
    if (_selected == null) {
      final total = _rows * _cols;
      final free = List.generate(total, (i) => i).where((i) => !_taken.contains(i)).toList();
      if (free.isNotEmpty) _selected = free[math.Random().nextInt(free.length)];
    }
    _popOnce();
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOut.transform(_appear.value).clamp(0.0, 1.0);
    final size = MediaQuery.of(context).size;
    final irisCenter = Offset(size.width / 2, size.height * 0.4);
    final irisT = Curves.easeInOutCubic.transform(_iris.value);
    final irisRadius = irisT * irisMaxRadius(size, irisCenter);
    final flashA = flashOpacity(_flash.value);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: SeenlyPalette.ink.withOpacity(0.34),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: DustPainter(t: _dust.value, motes: _motes)),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: const Alignment(0, -0.2),
                    child: Opacity(
                      opacity: (flashA * 0.5).clamp(0.0, 1.0),
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              SeenlyPalette.paper.withOpacity(0.75),
                              SeenlyPalette.paper.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Opacity(
                  opacity: appear,
                  child: Transform.translate(
                    offset: Offset(0, (1 - appear) * 12),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: GestureDetector(
                            onTap: _skip,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('skip'.tr,
                                  style: SeenlyText.mono(
                                      size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Text('find your seat'.tr,
                            style: SeenlyText.serif(
                                italic: true, size: 18, color: SeenlyPalette.paper)),
                        const SizedBox(height: 5),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _selected == null ? "tonight's ride".tr : "cozy — that one's yours".tr,
                            key: ValueKey(_selected == null),
                            style: SeenlyText.mono(
                                size: 10, color: SeenlyPalette.paper.withOpacity(0.68)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _RoutePlaque(route: _route, breathe: _breathe.value),
                        const SizedBox(height: 22),
                        const _AisleGlow(width: 190),
                        const SizedBox(height: 30),
                        for (int row = 0; row < _rows; row++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (int col = 0; col < _cols; col++) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 5),
                                    child: _CoachSeatButton(
                                      taken: _taken.contains(row * _cols + col),
                                      selected: _selected == row * _cols + col,
                                      onTap: () => _choose(row * _cols + col),
                                    ),
                                  ),
                                  if (col == 1) const SizedBox(width: 16), // the aisle
                                ],
                              ],
                            ),
                          ),
                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipPath(
                    clipper: IrisClipper(radius: irisRadius, center: irisCenter),
                    child: Container(color: SeenlyPalette.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small plaque showing the route tonight's runtime matched to — the
/// coach theme's stand-in for the cinema's marquee and the passport's
/// travel tag, same breathing glow so all three feel related.
class _RoutePlaque extends StatelessWidget {
  final CoachRoute route;
  final double breathe;

  const _RoutePlaque({required this.route, required this.breathe});

  @override
  Widget build(BuildContext context) {
    final intensity = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.3),
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.2 * intensity), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Text(
        '${route.originCity.toUpperCase()} → ${route.destCity.toUpperCase()}',
        textAlign: TextAlign.center,
        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
      ),
    );
  }
}

/// A soft glowing bar standing in for the coach's own aisle lighting.
class _AisleGlow extends StatelessWidget {
  final double width;
  const _AisleGlow({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.9),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.paper.withOpacity(0.36), blurRadius: 28, spreadRadius: 5),
        ],
      ),
    );
  }
}

class _CoachSeatButton extends StatelessWidget {
  final bool taken;
  final bool selected;
  final VoidCallback onTap;

  const _CoachSeatButton({required this.taken, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = taken
        ? SeenlyPalette.paper.withOpacity(0.16)
        : selected
            ? SeenlyPalette.accent
            : SeenlyPalette.paper.withOpacity(0.55);
    return GestureDetector(
      onTap: taken ? null : onTap,
      child: AnimatedScale(
        scale: selected ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: SeenlyPalette.accent.withOpacity(0.55), blurRadius: 14, spreadRadius: 1),
                  ],
                )
              : const BoxDecoration(),
          padding: const EdgeInsets.all(3),
          child: _CoachSeatShape(color: color, size: 19),
        ),
      ),
    );
  }
}

/// A tiny coach seat, drawn as a headrest sitting on a wider cushion —
/// the coach theme's equivalent of the cinema's little seat glyph, same
/// flat paper-cut shape language rather than a generic system icon.
class _CoachSeatShape extends StatelessWidget {
  final Color color;
  final double size;

  const _CoachSeatShape({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 0.66,
            height: size * 0.4,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.2)),
          ),
          const SizedBox(height: 1.5),
          Container(
            width: size,
            height: size * 0.34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.1)),
          ),
        ],
      ),
    );
  }
}
