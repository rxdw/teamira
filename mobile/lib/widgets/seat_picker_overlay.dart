import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart';
import '../services/app_translations.dart';

/// Plays right before the ticket lands in your hands: a tiny, warm
/// cinema of your own where you pick a seat for tonight's showing.
/// Nothing rides on which one — this is just the small, cozy pleasure
/// of choosing before the ticket appears, same spirit as picking a
/// blanket before you sit down.
///
/// The room "switches on" the way a projector does — a soft iris of
/// warm light blooming open from the center rather than a hard cut or
/// a heavy stage curtain (that's the "glossy box-office" look this app
/// deliberately moved away from — see [SeenlyPalette]). A handful of
/// dust motes drift in the beam, and the title gets its own tiny
/// marquee card with chasing bulb-lights, so the room feels inhabited
/// rather than just decorated.
///
/// Call [showSeatPicker] rather than constructing this directly — it
/// handles pushing the transparent route and popping itself off once a
/// seat is settled on (or skipped).
Future<void> showSeatPicker(
  BuildContext context, {
  required String title,
  required String mediaType,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _SeatPickerOverlay(title: title, mediaType: mediaType),
      ),
    ),
  );
}

class _SeatPickerOverlay extends StatefulWidget {
  final String title;
  final String mediaType;

  const _SeatPickerOverlay({required this.title, required this.mediaType});

  @override
  State<_SeatPickerOverlay> createState() => _SeatPickerOverlayState();
}

class _SeatPickerOverlayState extends State<_SeatPickerOverlay>
    with TickerProviderStateMixin {
  static const int _rows = 3;
  static const int _cols = 6;

  late final AnimationController _appear;
  late final AnimationController _iris; // one-shot: the lamp blooming open
  late final AnimationController _flash; // one-shot: the "click-on" glow
  late final AnimationController _dust; // loops: motes drifting in the beam
  late final AnimationController _chase; // loops: marquee bulb chase
  late final List<LightMote> _motes;
  late final Set<int> _taken;
  int? _selected;
  bool _popped = false;
  Timer? _advanceTimer;
  Timer? _watchdog;

  // The flashlight: wherever a finger currently is (or last was) once
  // the countdown's done — the room stays dark otherwise, and this is
  // the one small circle of light doing the finding. Locked in place
  // the instant a seat is chosen, so the room then floods outward from
  // *that* point rather than wherever the finger drifts to next.
  Offset? _torchPos;
  Offset? _lockedCenter;

  // A little film-leader countdown — 3…2…1 — plays before the room's
  // lamp switches on, the same "picture's about to start" beat as an
  // old reel counting down before the feature. Null once it's done (or
  // was skipped) and the iris is free to bloom open.
  int? _countdown = 3;
  Timer? _countdownTimer;
  static const Duration _countdownTick = Duration(milliseconds: 620);

  @override
  void initState() {
    super.initState();
    // A couple of seats are already "out" tonight — same title always
    // lands the same handful taken, so the room doesn't reshuffle if
    // this rebuilds. Just enough company to feel like a real little
    // showing, never so many it reads as a scramble for what's left.
    _taken = _seededTaken(widget.title, _rows * _cols);
    _motes = seededMotes(widget.title, 9);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() => setState(() {}))
      ..forward();
    // The iris and its click-on glow wait for the countdown now, rather
    // than firing immediately — see `_runCountdown`.
    _iris = AnimationController(vsync: this, duration: const Duration(milliseconds: 720))
      ..addListener(() => setState(() {}));
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..addListener(() => setState(() {}));
    _dust = AnimationController(vsync: this, duration: const Duration(seconds: 7))
      ..addListener(() => setState(() {}))
      ..repeat();
    _chase = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..addListener(() => setState(() {}))
      ..repeat();
    _runCountdown();
    // Nothing about this screen is essential — if nobody ever taps
    // (stuck frame, whatever), it should let go on its own rather than
    // becoming a wall between the person and their diary entry.
    _watchdog = Timer(const Duration(seconds: 20), _skip);
  }

  void _runCountdown() {
    _countdownTimer = Timer(_countdownTick, () {
      if (!mounted) return;
      final next = (_countdown ?? 1) - 1;
      if (next <= 0) {
        // Countdown's done, but the room stays dark — it only opens once
        // a seat is actually found and chosen, see `_choose`.
        setState(() => _countdown = null);
      } else {
        HapticFeedback.selectionClick();
        setState(() => _countdown = next);
        _runCountdown();
      }
    });
  }

  void _onTorchMove(PointerEvent event) {
    if (_selected != null) return; // locked in place once a seat's chosen
    setState(() => _torchPos = event.localPosition);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    _countdownTimer?.cancel();
    _appear.dispose();
    _iris.dispose();
    _flash.dispose();
    _dust.dispose();
    _chase.dispose();
    super.dispose();
  }

  static Set<int> _seededTaken(String seed, int total) {
    final r = math.Random(seed.hashCode);
    final count = 2 + r.nextInt(3); // 2-4 seats
    final taken = <int>{};
    while (taken.length < count && taken.length < total - 1) {
      taken.add(r.nextInt(total));
    }
    return taken;
  }

  void _choose(int index) {
    if (_selected != null || _taken.contains(index)) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selected = index;
      // The room floods outward from wherever the flashlight found the
      // seat, not from a fixed center — the payoff lands exactly where
      // the person was just looking.
      _lockedCenter = _torchPos;
    });
    _iris.forward();
    _flash.forward();
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 900), _popOnce);
  }

  void _skip() {
    if (_selected == null) {
      // Skipping the ritual shouldn't feel like refusing it — a seat
      // gets picked quietly on the person's behalf either way.
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

    // Where the light bloom falls back to before any finger's touched
    // the screen — roughly where the screen and marquee sit, so the
    // very first thing found (if nobody's dragged yet) is the room's
    // own light source.
    final defaultCenter = Offset(size.width / 2, size.height * 0.4);
    final searching = _countdown == null && _selected == null;
    final torchCenter = _torchPos ?? defaultCenter;

    final irisT = Curves.easeInOutCubic.transform(_iris.value);
    const searchRadius = 46.0;
    late final Offset irisCenter;
    late final double irisRadius;
    if (_countdown != null) {
      // Fully dark for the countdown — nothing to find yet.
      irisCenter = defaultCenter;
      irisRadius = 0;
    } else if (_selected == null) {
      // A small, gently breathing circle of light that goes wherever a
      // finger goes — this is the whole "find it yourself" beat.
      irisCenter = torchCenter;
      irisRadius = searchRadius + 5 * math.sin(_chase.value * 2 * math.pi);
    } else {
      // Locked at the moment of choosing, then blooms out from there
      // to fill the room.
      irisCenter = _lockedCenter ?? torchCenter;
      irisRadius = searchRadius + irisT * (irisMaxRadius(size, irisCenter) - searchRadius);
    }
    final flashA = flashOpacity(_flash.value);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: SeenlyPalette.ink.withOpacity(0.34),
          child: Listener(
            // Tracks a finger anywhere on the screen, so the flashlight
            // can follow it even before it's over a seat specifically —
            // translucent so taps still reach the seats underneath.
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onTorchMove,
            onPointerMove: _onTorchMove,
            child: Stack(
              children: [
                // Dust drifting in the beam — barely-there, just enough
                // for the room to feel like air rather than a flat
                // backdrop.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: DustPainter(t: _dust.value, motes: _motes),
                    ),
                  ),
                ),
                // The warm click-on glow, timed with the iris opening.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -0.2),
                      child: Opacity(
                        opacity: (flashA * 0.55).clamp(0.0, 1.0),
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                SeenlyPalette.mustard.withOpacity(0.85),
                                SeenlyPalette.mustard.withOpacity(0.0),
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
                          const Spacer(flex: 2),
                          Text('find your seat'.tr,
                              style: SeenlyText.serif(
                                  italic: true, size: 18, color: SeenlyPalette.paper)),
                          const SizedBox(height: 5),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _selected != null
                                  ? "cozy — that one's yours".tr
                                  : searching
                                      ? 'somewhere in here…'.tr
                                      : "tonight's ${widget.mediaType}",
                              key: ValueKey(_selected != null ? 2 : (searching ? 1 : 0)),
                              style: SeenlyText.mono(
                                  size: 10, color: SeenlyPalette.paper.withOpacity(0.68)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _MarqueeTitle(title: widget.title, chase: _chase.value),
                          const SizedBox(height: 22),
                          const _Screen(width: 210),
                          const SizedBox(height: 30),
                          for (int row = 0; row < _rows; row++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (int col = 0; col < _cols; col++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                      child: _SeatButton(
                                        taken: _taken.contains(row * _cols + col),
                                        selected: _selected == row * _cols + col,
                                        onTap: () => _choose(row * _cols + col),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const Spacer(flex: 3),
                        ],
                      ),
                    ),
                  ),
                ),
                // The flashlight itself: everything outside the small
                // (or, once chosen, growing) circle stays covered.
                // Ignoring pointers throughout so it never gets in the
                // way of actually picking a seat.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: IrisClipper(radius: irisRadius, center: irisCenter),
                      child: Container(color: SeenlyPalette.ink),
                    ),
                  ),
                ),
                // A soft rim of warm light right at the flashlight's own
                // edge, while it's still small and searching — otherwise
                // the circle's boundary reads as a flat cutout rather
                // than an actual beam.
                if (searching)
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TorchRimPainter(center: torchCenter, radius: irisRadius),
                    ),
                  ),
                // 3…2…1, film-leader style, while the room's still dark.
                if (_countdown != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: _FilmCountdown(value: _countdown!)),
                    ),
                  ),
                // The hint and the skip button both sit above the
                // darkness, always visible, since one explains the dark
                // and the other's the way out of it.
                if (searching)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: const Alignment(0, 0.86),
                        child: Opacity(
                          opacity: (0.55 + 0.45 * (0.5 + 0.5 * math.sin(_chase.value * 2 * math.pi)))
                              .clamp(0.0, 1.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flashlight_on,
                                  size: 13, color: SeenlyPalette.paper.withOpacity(0.75)),
                              const SizedBox(width: 6),
                              Text('drag to search the dark for your seat'.tr,
                                  style: SeenlyText.mono(
                                      size: 10, color: SeenlyPalette.paper.withOpacity(0.75))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _skip,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('skip'.tr,
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin ring of warm light traced right at the flashlight's own edge
/// — without this the circle reads as a flat cutout; with it, as an
/// actual beam with a soft, glowing rim.
class _TorchRimPainter extends CustomPainter {
  final Offset center;
  final double radius;

  const _TorchRimPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = SeenlyPalette.mustard.withOpacity(0.35);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _TorchRimPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}

/// The classic countdown-leader circle — a numeral inside a ring, with
/// a couple of faint tick marks standing in for a real reel's scratches
/// — punching in and settling for each beat rather than crossfading, so
/// it reads as mechanical rather than a soft UI transition.
class _FilmCountdown extends StatelessWidget {
  final int value;
  const _FilmCountdown({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 1.35, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 108,
        height: 108,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SeenlyPalette.ink.withOpacity(0.5),
          border: Border.all(color: SeenlyPalette.paper.withOpacity(0.55), width: 2.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // A couple of thin radial ticks, like a real leader's crosshair.
            for (int i = 0; i < 4; i++)
              Transform.rotate(
                angle: i * math.pi / 2,
                child: Container(
                  width: 1.4,
                  height: 108,
                  color: SeenlyPalette.paper.withOpacity(0.14),
                ),
              ),
            Text(
              '$value',
              style: SeenlyText.mono(size: 46, color: SeenlyPalette.paper, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny marquee card announcing tonight's title, bulb-lights chasing
/// around the border the way a real cinema marquee's do — small and
/// warm rather than loud, but the one detail on this screen that's
/// actually about *this* evening rather than the ritual in general.
class _MarqueeTitle extends StatelessWidget {
  final String title;
  final double chase;

  const _MarqueeTitle({required this.title, required this.chase});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: SeenlyPalette.ink.withOpacity(0.3),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: SeenlyPalette.paper.withOpacity(0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bulbRow(0),
          const SizedBox(height: 7),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          _bulbRow(0.5),
        ],
      ),
    );
  }

  Widget _bulbRow(double offset) {
    const count = 9;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(count, (i) {
        final t = (chase + offset + i / count) % 1.0;
        final glow = 0.3 + 0.7 * ((math.sin(t * math.pi * 2) + 1) / 2);
        return Container(
          width: 3.4,
          height: 3.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeenlyPalette.mustard.withOpacity(glow),
            boxShadow: [
              BoxShadow(
                color: SeenlyPalette.mustard.withOpacity(glow * 0.6),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// A soft glowing bar standing in for the screen — the room's one light
/// source, warm rather than the cold white-blue of an actual projector.
class _Screen extends StatelessWidget {
  final double width;
  const _Screen({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 9,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.92),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.paper.withOpacity(0.4),
            blurRadius: 34,
            spreadRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _SeatButton extends StatelessWidget {
  final bool taken;
  final bool selected;
  final VoidCallback onTap;

  const _SeatButton({required this.taken, required this.selected, required this.onTap});

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
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SeenlyPalette.accent.withOpacity(0.55),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                )
              : const BoxDecoration(),
          padding: const EdgeInsets.all(3),
          child: _SeatShape(color: color, size: 19),
        ),
      ),
    );
  }
}

/// A tiny theater seat drawn from two rounded blocks — backrest sitting
/// on a slightly wider base — kept in the same flat, paper-cut shape
/// language as the rest of the app rather than borrowing a generic
/// system icon.
class _SeatShape extends StatelessWidget {
  final Color color;
  final double size;

  const _SeatShape({required this.color, required this.size});

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
            width: size * 0.6,
            height: size * 0.46,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.16),
            ),
          ),
          const SizedBox(height: 1.5),
          Container(
            width: size,
            height: size * 0.3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

// Dust motes, the iris clipper, and the flash curve now live in
// light_bloom.dart, shared with the coach theme's boarding overlay.
