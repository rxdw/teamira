import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// Plays right before tonight's evening takes root — the garden theme's
/// answer to the cinema's seat and the coach's seat: a small window box
/// of empty spots, waiting for you to choose where tonight's seed goes
/// before it actually drops in and sprouts. Nothing rides on which spot
/// — same small, cozy pleasure of choosing as the other two themes, not
/// a functional control.
///
/// A spot or two is already grown in tonight — the same seeded "a
/// couple are already taken" touch as the cinema and the coach — so the
/// box feels lived-in rather than sitting empty just for you.
///
/// Call [showGardenPlant] rather than building this directly — it
/// handles pushing the transparent route and popping itself once a
/// spot is chosen (or skipped).
Future<void> showGardenPlant(
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
        child: _GardenPlantOverlay(title: title, mediaType: mediaType),
      ),
    ),
  );
}

class _GardenPlantOverlay extends StatefulWidget {
  final String title;
  final String mediaType;
  const _GardenPlantOverlay({required this.title, required this.mediaType});

  @override
  State<_GardenPlantOverlay> createState() => _GardenPlantOverlayState();
}

class _GardenPlantOverlayState extends State<_GardenPlantOverlay> with TickerProviderStateMixin {
  static const int _slots = 5;

  late final AnimationController _appear;
  late final AnimationController _grow; // one-shot: seed drop + sprout, once a spot's chosen
  late final AnimationController _sway; // loops: a gentle breeze over the box
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
    _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 780))
      ..addListener(() => setState(() {}));
    _sway = AnimationController(vsync: this, duration: const Duration(seconds: 4))
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
    _grow.dispose();
    _sway.dispose();
    super.dispose();
  }

  static Set<int> _seededTaken(String seed, int total) {
    // Same title always lands the same spot or two already grown, so the
    // box doesn't reshuffle if this rebuilds.
    final r = math.Random(seed.hashCode ^ 0x67726F77); // 'grow'
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
    _grow.forward(from: 0);
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
      color: SeenlyPalette.ink.withOpacity(0.42),
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
                      child: Text('skip'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.75))),
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
                    _selected == null ? 'choose a spot for tonight'.tr : 'tucking it into the bed…'.tr,
                    key: ValueKey(_selected == null),
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.72)),
                  ),
                ),
                const SizedBox(height: 30),
                _WindowBoxPicker(
                  slots: _slots,
                  taken: _taken,
                  selected: _selected,
                  grow: _grow,
                  sway: _sway.value,
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

/// The little window box of planting spots itself — a soil trough with
/// a row of mounds, most empty and tappable, a couple already grown in.
/// Choosing an empty one plays the seed dropping in and the sprout
/// pushing up right there in its spot.
class _WindowBoxPicker extends StatelessWidget {
  final int slots;
  final Set<int> taken;
  final int? selected;
  final AnimationController grow;
  final double sway; // 0..1..0, a gentle loop
  final ValueChanged<int> onTap;

  const _WindowBoxPicker({
    required this.slots,
    required this.taken,
    required this.selected,
    required this.grow,
    required this.sway,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swayDeg = (sway - 0.5) * 3;
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
                  _Spot(
                    isTaken: taken.contains(i),
                    isSelected: selected == i,
                    isChosenElsewhere: selected != null && selected != i,
                    grow: grow,
                    swayDeg: swayDeg,
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
                colors: [SeenlyPalette.mustard, Color(0xFFB9863C)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spot extends StatelessWidget {
  final bool isTaken;
  final bool isSelected;
  final bool isChosenElsewhere;
  final AnimationController grow;
  final double swayDeg;
  final VoidCallback onTap;

  const _Spot({
    required this.isTaken,
    required this.isSelected,
    required this.isChosenElsewhere,
    required this.grow,
    required this.swayDeg,
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
              ? _grownStem(alreadyThere: true)
              : isSelected
                  ? AnimatedBuilder(animation: grow, builder: (_, __) => _growingStem())
                  : Transform.rotate(
                      angle: swayDeg * math.pi / 180 * 0.5,
                      alignment: Alignment.bottomCenter,
                      child: _emptyMound(),
                    ),
        ),
      ),
    );
  }

  Widget _emptyMound() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.add, size: 13, color: SeenlyPalette.inkFaint.withOpacity(0.5)),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: 8,
          decoration: BoxDecoration(
            color: SeenlyPalette.cork,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _grownStem({required bool alreadyThere}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: SeenlyPalette.sage, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(Icons.eco, size: 10, color: SeenlyPalette.paper),
        ),
        const SizedBox(height: 3),
        Container(width: 2.4, height: 26, color: SeenlyPalette.sage.withOpacity(0.8)),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 8,
          decoration: BoxDecoration(color: SeenlyPalette.cork, borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }

  Widget _growingStem() {
    final drop = CurvedAnimation(parent: grow, curve: const Interval(0, 0.4, curve: Curves.easeIn)).value;
    final sprout = CurvedAnimation(parent: grow, curve: const Interval(0.4, 1, curve: Curves.easeOutBack)).value;
    final dropY = 4 + drop * 22;
    final sproutH = 26 * sprout.clamp(0.0, 1.0).toDouble();
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
              decoration: BoxDecoration(color: SeenlyPalette.cork, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Positioned(bottom: 6, child: Container(width: 2.4, height: sproutH, color: SeenlyPalette.sage)),
          Positioned(
            bottom: 6 + sproutH - 4,
            child: Opacity(
              opacity: sprout.clamp(0.0, 1.0).toDouble(),
              child: Icon(Icons.eco, size: 15, color: SeenlyPalette.sage),
            ),
          ),
          if (drop < 1)
            Positioned(
              top: dropY,
              child: Opacity(
                opacity: (1 - sprout).clamp(0.0, 1.0).toDouble(),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: SeenlyPalette.clay, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
