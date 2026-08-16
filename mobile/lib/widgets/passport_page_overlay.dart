import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart';
import '../services/app_translations.dart';

/// The passport theme's counterpart to `seat_picker_overlay.dart`:
/// instead of a mini cinema, a passport lying open on a desk, waiting
/// for you to settle on which blank page tonight's stamp lands on.
/// Same small, cozy pleasure of choosing before the mark appears —
/// nothing rides on which page, it's just a moment in your hands.
///
/// The desk "switches on" the same way the cinema's lamp does — a soft
/// iris of warm light blooming open from the center — and the same
/// drifting motes catch it, so the two rituals read as one idea worn
/// two ways rather than unrelated screens. The title gets its own
/// little travel tag instead of a marquee, with a slow breathing glow
/// standing in for chasing bulb-lights.
///
/// Call [showPassportPage] rather than constructing this directly.
Future<void> showPassportPage(
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
        child: _PassportPageOverlay(title: title, mediaType: mediaType),
      ),
    ),
  );
}

class _PassportPageOverlay extends StatefulWidget {
  final String title;
  final String mediaType;

  const _PassportPageOverlay({required this.title, required this.mediaType});

  @override
  State<_PassportPageOverlay> createState() => _PassportPageOverlayState();
}

class _PassportPageOverlayState extends State<_PassportPageOverlay>
    with TickerProviderStateMixin {
  static const int _rows = 3;
  static const int _cols = 6;

  late final AnimationController _appear;
  late final AnimationController _iris;
  late final AnimationController _flash;
  late final AnimationController _dust;
  late final AnimationController _breathe; // loops: the travel tag's glow
  late final List<LightMote> _motes;
  late final Set<int> _stamped;
  int? _selected;
  bool _popped = false;
  Timer? _advanceTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    // A few pages already carry a stamp from other evenings — same
    // title always lands the same handful used, so the spread doesn't
    // reshuffle on rebuild.
    _stamped = _seededStamped(widget.title, _rows * _cols);
    _motes = seededMotes(widget.title, 9, salt: 0x70706173); // 'ppas'
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

  static Set<int> _seededStamped(String seed, int total) {
    final r = math.Random(seed.hashCode ^ 0x70706173);
    final count = 2 + r.nextInt(3); // 2-4 pages
    final used = <int>{};
    while (used.length < count && used.length < total - 1) {
      used.add(r.nextInt(total));
    }
    return used;
  }

  void _choose(int index) {
    if (_selected != null || _stamped.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 750), _popOnce);
  }

  void _skip() {
    if (_selected == null) {
      final total = _rows * _cols;
      final free = List.generate(total, (i) => i).where((i) => !_stamped.contains(i)).toList();
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
                              SeenlyPalette.paper.withOpacity(0.8),
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
                        Text('find a blank page'.tr,
                            style: SeenlyText.serif(
                                italic: true, size: 18, color: SeenlyPalette.paper)),
                        const SizedBox(height: 5),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _selected == null
                                ? "tonight's ${widget.mediaType}"
                                : "there — save it for tonight",
                            key: ValueKey(_selected == null),
                            style: SeenlyText.mono(
                                size: 10, color: SeenlyPalette.paper.withOpacity(0.68)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _TravelTag(title: widget.title, breathe: _breathe.value),
                        const SizedBox(height: 22),
                        const _DeskGlow(width: 190),
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
                                    child: _PageButton(
                                      stamped: _stamped.contains(row * _cols + col),
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

/// A small travel tag announcing tonight's title, with a slow breathing
/// glow standing in for the marquee's chasing bulbs — quieter and more
/// "worn leather" than "lit-up box office", to match the theme.
class _TravelTag extends StatelessWidget {
  final String title;
  final double breathe;

  const _TravelTag({required this.title, required this.breathe});

  @override
  Widget build(BuildContext context) {
    final intensity = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return ClipPath(
      clipper: _TagClipper(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(20, 9, 16, 9),
        decoration: BoxDecoration(
          color: SeenlyPalette.ink.withOpacity(0.3),
          boxShadow: [
            BoxShadow(
              color: SeenlyPalette.mustard.withOpacity(0.22 * intensity),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeenlyPalette.mustard.withOpacity(intensity),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded rectangle with a tiny punched hole near the left edge — the
/// string-hole of a real luggage tag.
class _TagClipper extends CustomClipper<Path> {
  const _TagClipper();

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    final hole = Path()..addOval(Rect.fromCircle(center: Offset(10, size.height / 2), radius: 2.4));
    return Path.combine(PathOperation.difference, base, hole);
  }

  @override
  bool shouldReclip(covariant _TagClipper oldDelegate) => false;
}

/// A soft glowing bar standing in for the desk lamp's own light — the
/// passport theme's equivalent of the cinema's screen glow.
class _DeskGlow extends StatelessWidget {
  final double width;
  const _DeskGlow({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.9),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.paper.withOpacity(0.38),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final bool stamped;
  final bool selected;
  final VoidCallback onTap;

  const _PageButton({required this.stamped, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = stamped
        ? SeenlyPalette.paper.withOpacity(0.16)
        : selected
            ? SeenlyPalette.accent
            : SeenlyPalette.paper.withOpacity(0.55);
    return GestureDetector(
      onTap: stamped ? null : onTap,
      child: AnimatedScale(
        scale: selected ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
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
          child: _PageShape(color: color, stamped: stamped, size: 19),
        ),
      ),
    );
  }
}

/// A tiny dog-eared page — a rectangle with its corner folded down —
/// kept in the same flat, paper-cut shape language as the ticket
/// theme's seat rather than a generic system icon. Already-used pages
/// carry a faint ink dot, echoing the stamp they'll eventually hold.
class _PageShape extends StatelessWidget {
  final Color color;
  final bool stamped;
  final double size;

  const _PageShape({required this.color, required this.stamped, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipPath(
            clipper: _DogEarClipper(),
            child: Container(color: color),
          ),
          if (stamped)
            Positioned(
              left: size * 0.32,
              top: size * 0.32,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeenlyPalette.ink.withOpacity(0.22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DogEarClipper extends CustomClipper<Path> {
  const _DogEarClipper();

  @override
  Path getClip(Size size) {
    final fold = size.width * 0.34;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _DogEarClipper oldDelegate) => false;
}
