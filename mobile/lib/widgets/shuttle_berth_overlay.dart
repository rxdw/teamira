import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// Plays right before tonight's evening lifts off — the shuttle
/// theme's answer to the cinema's seat, the coach's seat, and the
/// garden's spot: a small row of docking berths, waiting for you to
/// choose one before tonight actually launches. Nothing rides on
/// which berth — same small pleasure of choosing as the other three
/// themes, not a functional control.
///
/// A berth or two is already docked tonight — the same seeded "a
/// couple are already taken" touch as the other themes — so the pad
/// feels lived-in rather than sitting empty just for you.
///
/// Call [showShuttleBerth] rather than building this directly — it
/// handles pushing the transparent route and popping itself once a
/// berth is chosen (or skipped).
Future<void> showShuttleBerth(
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
        child: _ShuttleBerthOverlay(title: title, mediaType: mediaType),
      ),
    ),
  );
}

class _ShuttleBerthOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  const _ShuttleBerthOverlay({required this.title, required this.mediaType});

  @override
  State<_ShuttleBerthOverlay> createState() => _ShuttleBerthOverlayState();
}

class _ShuttleBerthOverlayState extends State<_ShuttleBerthOverlay> with TickerProviderStateMixin {
  static const int _slots = 5;

  late final AnimationController _appear;
  late final AnimationController _dock; // one-shot: pod door closes + engines light, once a berth's chosen
  late final AnimationController _blink; // loops: a slow beacon blink over the pad
  late final Set<int> _taken;

  int? _selected;
  bool _popped = false;
  Timer? _advanceTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _taken = _seededTaken(widget.title, _slots);
    _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() => setState(() {}))
      ..forward();
    _dock = AnimationController(vsync: this, duration: const Duration(milliseconds: 780))
      ..addListener(() => setState(() {}));
    _blink = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
    // Nothing about this screen is essential — if nobody ever taps, it
    // should let go on its own rather than blocking the way to the diary.
    _watchdog = Timer(const Duration(seconds: 20), _skip);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    _appear.dispose();
    _dock.dispose();
    _blink.dispose();
    super.dispose();
  }

  static Set<int> _seededTaken(String seed, int total) {
    // Same title always lands the same berth or two already docked, so
    // the pad doesn't reshuffle if this rebuilds.
    final r = math.Random(seed.hashCode ^ 0x646F636B); // 'dock'
    final count = 1 + r.nextInt(2);
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
    _dock.forward(from: 0);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 1150), _popOnce);
  }

  void _skip() {
    if (_selected == null) {
      final free = List.generate(_slots, (i) => i).where((i) => !_taken.contains(i)).toList();
      if (free.isNotEmpty) _selected = free[math.Random().nextInt(free.length)];
    }
    _popOnce();
  }

  void _popOnce() {
    if (_popped || !mounted) return;
    _popped = true;
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOut.transform(_appear.value).clamp(0.0, 1.0).toDouble();
    return Container(
      color: const Color(0xFF171A2E).withOpacity(0.82),
      child: SafeArea(
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
                      child:
                          Text('skip'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.75))),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(italic: true, size: 17, weight: FontWeight.w600, color: SeenlyPalette.paper),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _selected == null ? 'choose a berth for tonight'.tr : 'sealing the hatch…'.tr,
                    key: ValueKey(_selected == null),
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.72)),
                  ),
                ),
                const SizedBox(height: 30),
                _LaunchPadPicker(
                  slots: _slots,
                  taken: _taken,
                  selected: _selected,
                  dock: _dock,
                  blink: _blink.value,
                  onTap: _choose,
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The little launch pad of berths itself — a docking rail with a row
/// of pods, most empty and tappable, a couple already docked. Choosing
/// an empty one plays the hatch sealing and the engines lighting right
/// there in its spot.
class _LaunchPadPicker extends StatelessWidget {
  final int slots;
  final Set<int> taken;
  final int? selected;
  final AnimationController dock;
  final double blink; // 0..1..0, a slow loop
  final ValueChanged<int> onTap;

  const _LaunchPadPicker({
    required this.slots,
    required this.taken,
    required this.selected,
    required this.dock,
    required this.blink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 78,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < slots; i++)
                  _Berth(
                    isTaken: taken.contains(i),
                    isSelected: selected == i,
                    isChosenElsewhere: selected != null && selected != i,
                    dock: dock,
                    blink: blink,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SeenlyPalette.periwinkle, const Color(0xFF3C4A8C)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Berth extends StatelessWidget {
  final bool isTaken;
  final bool isSelected;
  final bool isChosenElsewhere;
  final AnimationController dock;
  final double blink;
  final VoidCallback onTap;

  const _Berth({
    required this.isTaken,
    required this.isSelected,
    required this.isChosenElsewhere,
    required this.dock,
    required this.blink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (isTaken || isChosenElsewhere) ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: isChosenElsewhere ? 0.35 : 1,
        duration: const Duration(milliseconds: 220),
        child: SizedBox(
          width: 40,
          child: isTaken
              ? _dockedPod(alreadyThere: true)
              : isSelected
                  ? AnimatedBuilder(animation: dock, builder: (_, __) => _dockingPod())
                  : _emptyPod(),
        ),
      ),
    );
  }

  Widget _emptyPod() {
    final glow = 0.35 + blink * 0.25;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.add, size: 13, color: SeenlyPalette.inkFaint.withOpacity(0.5)),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: 8,
          decoration: BoxDecoration(
            color: SeenlyPalette.inkFaint.withOpacity(glow * 0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: SeenlyPalette.periwinkle.withOpacity(glow)),
          ),
        ),
      ],
    );
  }

  Widget _dockedPod({required bool alreadyThere}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: SeenlyPalette.periwinkle, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.rocket_launch, size: 10, color: SeenlyPalette.paper),
        ),
        const SizedBox(height: 3),
        Container(width: 2.4, height: 26, color: SeenlyPalette.periwinkle.withOpacity(0.8)),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 8,
          decoration:
              BoxDecoration(color: SeenlyPalette.periwinkle.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }

  Widget _dockingPod() {
    // Hatch seal, then the engines light — a mirror of the garden
    // theme's drop-then-sprout beat, dressed as launch prep instead.
    final seal = CurvedAnimation(parent: dock, curve: const Interval(0, 0.4, curve: Curves.easeIn)).value;
    final ignite = CurvedAnimation(parent: dock, curve: const Interval(0.4, 1, curve: Curves.easeOutBack)).value;
    final sealY = 4 + seal * 22;
    final podH = 26 * ignite.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 62,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 22,
              height: 8,
              decoration: BoxDecoration(color: SeenlyPalette.periwinkle.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Positioned(bottom: 6, child: Container(width: 2.4, height: podH, color: SeenlyPalette.periwinkle)),
          Positioned(
            bottom: 6 + podH - 4,
            child: Opacity(
              opacity: ignite.clamp(0.0, 1.0).toDouble(),
              child: Icon(Icons.rocket_launch, size: 15, color: SeenlyPalette.periwinkle),
            ),
          ),
          if (seal < 1)
            Positioned(
              top: sealY,
              child: Opacity(
                opacity: (1 - ignite).clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
