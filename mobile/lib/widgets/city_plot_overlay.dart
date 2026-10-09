import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'light_bloom.dart';
import '../services/app_translations.dart';

/// The "Город из просмотренного" theme's counterpart to the seat, page,
/// and coach-seat pickers: a quiet strip at the edge of the skyline,
/// some of it already built up, a few open plots waiting. Same small,
/// cozy pleasure of choosing before the mark appears — nothing rides on
/// which plot, every one of them ends up in the same skyline either way.
///
/// The street lamp along the block "switches on" the same warm-bloom
/// way the cinema's lamp, the passport's desk light, and the coach's
/// aisle light all do, so all four rituals read as one idea worn four
/// ways. A small "lot for sale" sign stands in for the marquee/travel
/// tag/route plaque.
///
/// Call [showCityPlot] rather than constructing this directly.
Future<void> showCityPlot(
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
        child: _CityPlotOverlay(title: title, mediaType: mediaType),
      ),
    ),
  );
}

class _CityPlotOverlay extends StatefulWidget {
  final String title;
  final String mediaType;

  const _CityPlotOverlay({required this.title, required this.mediaType});

  @override
  State<_CityPlotOverlay> createState() => _CityPlotOverlayState();
}

class _CityPlotOverlayState extends State<_CityPlotOverlay> with TickerProviderStateMixin {
  static const int _slots = 9;

  late final AnimationController _appear;
  late final AnimationController _iris;
  late final AnimationController _flash;
  late final AnimationController _dust;
  late final AnimationController _breathe;
  late final List<LightMote> _motes;
  late final Set<int> _built; // already-standing silhouettes, not selectable
  late final List<double> _silhouetteHeights;
  int? _selected;
  bool _popped = false;
  Timer? _advanceTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _built = _seededBuilt(widget.title, _slots);
    _silhouetteHeights = List.generate(
        _slots, (i) => _built.contains(i) ? 0.35 + boardingLikeJitter(widget.title, 0, 0.6, salt: i) : 0.0);
    _motes = seededMotes(widget.title, 9, salt: 0x63697479); // 'city'
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

  static Set<int> _seededBuilt(String seed, int total) {
    final r = math.Random(seed.hashCode ^ 0x63697479);
    final openCount = 2 + r.nextInt(2); // 2-3 open plots
    final open = <int>{};
    while (open.length < openCount) {
      open.add(r.nextInt(total));
    }
    return {for (var i = 0; i < total; i++) if (!open.contains(i)) i};
  }

  void _choose(int index) {
    if (_selected != null || _built.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 750), _popOnce);
  }

  void _skip() {
    if (_selected == null) {
      final free = List.generate(_slots, (i) => i).where((i) => !_built.contains(i)).toList();
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
    final irisCenter = Offset(size.width / 2, size.height * 0.42);
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
                    alignment: const Alignment(0, -0.15),
                    child: Opacity(
                      opacity: (flashA * 0.5).clamp(0.0, 1.0),
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [SeenlyPalette.mustard.withOpacity(0.7), SeenlyPalette.mustard.withOpacity(0.0)],
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
                                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.7))),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Text('choose a plot'.tr,
                            style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)),
                        const SizedBox(height: 5),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _selected == null ? "tonight's ${widget.mediaType}" : "there — build here".tr,
                            key: ValueKey(_selected == null),
                            style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper.withOpacity(0.68)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _LotSign(title: widget.title, breathe: _breathe.value),
                        const Spacer(flex: 3),
                        // The block itself: silhouettes already standing,
                        // a couple of open, glowing plots waiting.
                        SizedBox(
                          height: 96,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < _slots; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: _PlotSlot(
                                    built: _built.contains(i),
                                    silhouetteHeight: _silhouetteHeights[i],
                                    selected: _selected == i,
                                    onTap: () => _choose(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(height: 3, margin: const EdgeInsets.only(top: 2), color: SeenlyPalette.paper.withOpacity(0.12)),
                        const Spacer(flex: 2),
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

/// A small "lot for sale" sign with the title on it — the city theme's
/// stand-in for the marquee/travel tag/route plaque, same breathing
/// glow so all four themes feel related.
class _LotSign extends StatelessWidget {
  final String title;
  final double breathe;

  const _LotSign({required this.title, required this.breathe});

  @override
  Widget build(BuildContext context) {
    final intensity = 0.35 + 0.65 * ((math.sin(breathe * 2 * math.pi) + 1) / 2);
    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: SeenlyPalette.ink.withOpacity(0.3),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(color: SeenlyPalette.mustard.withOpacity(0.2 * intensity), blurRadius: 12, spreadRadius: 1),
            ],
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.paper, weight: FontWeight.w600),
          ),
        ),
        Container(width: 1.4, height: 12, color: SeenlyPalette.paper.withOpacity(0.3)),
      ],
    );
  }
}

class _PlotSlot extends StatelessWidget {
  final bool built;
  final double silhouetteHeight; // 0..1, only meaningful when built
  final bool selected;
  final VoidCallback onTap;

  const _PlotSlot({
    required this.built,
    required this.silhouetteHeight,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (built) {
      return Container(
        width: 22,
        height: 96 * silhouetteHeight,
        decoration: BoxDecoration(
          color: SeenlyPalette.ink.withOpacity(0.55),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: Container(
          width: 22,
          height: selected ? 34 : 16,
          decoration: BoxDecoration(
            color: selected ? SeenlyPalette.accent : SeenlyPalette.paper.withOpacity(0.4),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            boxShadow: selected
                ? [BoxShadow(color: SeenlyPalette.accent.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)]
                : null,
          ),
        ),
      ),
    );
  }
}

/// Deterministic pseudo-random value in `[min, max]` for a given seed —
/// mirrors `seededJitter` in `ticket.dart`, kept local so this file has
/// no dependency on the ticket theme.
double boardingLikeJitter(Object seed, double min, double max, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt);
  return min + r.nextDouble() * (max - min);
}
