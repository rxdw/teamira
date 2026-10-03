import 'package:flutter/material.dart';

import '../services/log_theme_service.dart';
import '../theme/log_theme_copy.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// Dresses up "the log" — the day-by-day list under the diary
/// centerpiece — so it reads as a kept scrapbook rather than a plain
/// list view, without turning it into another poster carousel (that
/// idiom already belongs to Collections). Two small, cheap ideas do
/// almost all the work:
///
/// 1. A soft dashed thread runs down the left of the whole log, one
///    themed waypoint per day (a seed, a train, a torn stub — see
///    [LogThemeCopy.avatarBadgeIcon]) — the same "still going" feeling
///    [DiaryCenterpiece] already sells, just carried into the list
///    itself instead of stopping at the jar/board/garden above it.
/// 2. Every entry card gets a hair of random-feeling tilt and a strip
///    of washi tape in the corner, like it was actually pressed onto
///    a page — cheap in Flutter (one Transform.rotate, one small
///    rotated rectangle) but it's the single biggest lever for
///    "cozy, handmade" over "generic list row". The ticket theme adds
///    one more: two punched notches in the card's long edges, so an
///    evening logged under that theme actually reads as a torn stub
///    you'd keep in a jar.
///
/// Everything here is presentational only — [entries] keep whatever
/// widget already rendered them (_DiaryRow / _SeriesEntryRow); this
/// file only wraps and threads them together.

/// One accent color per [LogTheme] so the thread, the waypoint dot, and
/// the date pill all agree — reuses colors already meaningful elsewhere
/// (sage already means "garden" on the avatar badge; clay/mustard are
/// otherwise-unclaimed categoricals, so coach/ticket get their own
/// rather than sharing sage's leftovers).
Color logThemeAccent(LogTheme theme) => switch (theme) {
      LogTheme.garden => SeenlyPalette.sage,
      LogTheme.coach => SeenlyPalette.clay,
      LogTheme.ticket => SeenlyPalette.mustard,
      LogTheme.shuttle => SeenlyPalette.periwinkle,
    };

/// The washi-tape corner rotates through these three across entries so
/// a long log doesn't read as the same sticker repeated — same trio
/// [SeenlyPalette] already reserves for tape accents elsewhere.
final List<Color> _tapeColors = [
  SeenlyPalette.tapeRose,
  SeenlyPalette.tapeSage,
  SeenlyPalette.tapeMustard,
];

/// A short dashed line, oriented vertically, the width of [thickness].
/// Used for the timeline's connecting thread. Deliberately hand-drawn
/// rather than a solid rule — a solid line reads as a UI divider, a
/// dashed one reads as a stitched or sketched path, which is the
/// feeling every one of the three themes is going for (a garden path,
/// a rail line, a length of string through punched tickets).
class _DashedLine extends StatelessWidget {
  final Color color;
  final double thickness;
  const _DashedLine({required this.color, this.thickness = 2});

  @override
  Widget build(BuildContext context) {
    // No LayoutBuilder here on purpose: this sits inside an Expanded
    // inside a Column that LogDayGroup measures with IntrinsicHeight,
    // and LayoutBuilder's RenderObject doesn't support intrinsic-size
    // queries at all (it throws) — which used to blow up the whole
    // sliver's layout the moment this widget was in the tree. A bare
    // CustomPaint over a SizedBox.expand has no such restriction and
    // still fills exactly the tight height Expanded hands it.
    return CustomPaint(
      painter: _DashedLinePainter(color: color, thickness: thickness),
      child: const SizedBox.expand(),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double thickness;
  const _DashedLinePainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 4.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thickness != thickness;
}

/// One day's waypoint on the thread — a small filled circle in the
/// theme's accent, carrying the same icon the avatar badge and nav
/// tab already use for this theme, with a paper ring so it lifts off
/// the dashed line running through it.
class _DayWaypoint extends StatelessWidget {
  final LogTheme theme;
  const _DayWaypoint({required this.theme});

  @override
  Widget build(BuildContext context) {
    final color = logThemeAccent(theme);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: SeenlyPalette.background, width: 3),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(LogThemeCopy.avatarBadgeIcon(theme), size: 10, color: SeenlyPalette.paper),
    );
  }
}

/// One day-group of the log: a waypoint + date pill on the thread,
/// with that day's entries stacked underneath, all sharing one
/// continuous stretch of dashed thread down the left. [IntrinsicHeight]
/// lets the thread stretch to match the entries column's real height
/// without this widget needing to measure anything itself — the whole
/// block (header + every entry that day) is small enough that the
/// extra layout pass is unnoticeable.
class LogDayGroup extends StatelessWidget {
  final LogTheme theme;
  final String dayLabel;
  final List<Widget> entries;
  final int tapeStartIndex;

  const LogDayGroup({
    super.key,
    required this.theme,
    required this.dayLabel,
    required this.entries,
    this.tapeStartIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final accent = logThemeAccent(theme);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                _DayWaypoint(theme: theme),
                Expanded(child: _DashedLine(color: accent.withOpacity(0.45))),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Nudged up to sit level with the waypoint circle
                  // rather than its vertical center.
                  padding: const EdgeInsets.only(top: 0, bottom: 12),
                  child: Text(dayLabel,
                      style: SeenlyText.diaryDate(size: 17, color: accent)),
                ),
                for (int i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ScrapbookEntry(
                      theme: theme,
                      index: tapeStartIndex + i,
                      child: entries[i],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps one entry card with a hair of tilt, a piece of washi tape, and
/// a scroll-driven reveal: the card fades and eases up into place as
/// it's scrolled onto screen, tied to the list's own [ScrollController]
/// rather than a fire-once entrance animation, so it responds to the
/// person's actual scrolling — flick fast and it catches up, scroll
/// slowly and it eases in at that same unhurried pace, scroll back down
/// and it recedes again. That direct, reversible link to the finger on
/// the screen is what "presence" means here.
///
/// Rotation alternates by parity of [index] (deterministic, not
/// [Random] — a rebuild must never make a card visibly jitter to a new
/// angle) and stays under 2° so the card is still fully legible; tape
/// color cycles through the app's three tape tones. The ticket theme
/// layers on one more touch: two small notches punched in the card's
/// left/right edges, so a logged evening reads as an actual torn stub.
class ScrapbookEntry extends StatefulWidget {
  final LogTheme theme;
  final int index;
  final Widget child;
  const ScrapbookEntry({super.key, required this.theme, required this.index, required this.child});

  @override
  State<ScrapbookEntry> createState() => _ScrapbookEntryState();
}

class _ScrapbookEntryState extends State<ScrapbookEntry> {
  // 0 = still below the fold, not yet revealed; 1 = fully settled into
  // place. Kept as plain state (not an AnimationController) because the
  // driving value isn't time, it's scroll offset — the position updates
  // every scroll tick, and Flutter's own frame-to-frame Opacity/Transform
  // diffing already makes that read as smooth motion without a ticker of
  // its own to manage.
  double _t = 0;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    final newPosition = scrollable?.position;
    if (newPosition != _position) {
      _position?.removeListener(_onScroll);
      _position = newPosition;
      _position?.addListener(_onScroll);
      // First measurement has to wait for this frame's layout to land
      // (can't measure a RenderBox mid-build), otherwise every card
      // would flash invisible for a frame on first open.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final scrollableBox = Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || scrollableBox == null || !scrollableBox.attached) return;
    final itemTop = box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
    final viewportHeight = scrollableBox.size.height;
    // The card starts easing in once its top crosses the bottom edge of
    // the viewport, and finishes settling [_revealWindow] pixels of
    // scrolling later — comfortably before it reaches reading position,
    // so nothing is still visibly animating where the eye actually
    // lands.
    const revealWindow = 190.0;
    final t = ((viewportHeight - itemTop) / revealWindow).clamp(0.0, 1.0);
    if ((t - _t).abs() > 0.004) {
      setState(() => _t = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final angle = (widget.index.isEven ? -1 : 1) * 0.018;
    final tape = _tapeColors[widget.index % _tapeColors.length];
    // Cards alternate which side they ease in from, same parity as the
    // tilt — a left-tilted card also drifts in from the left, so the
    // two feel like one physical motion (tucking a card in at a slight
    // angle) instead of two unrelated effects layered on the same card.
    final driftX = (widget.index.isEven ? -1 : 1) * 22.0 * (1 - _t);

    Widget card = Transform.rotate(angle: angle, child: widget.child);

    if (widget.theme == LogTheme.ticket) {
      // Two small circles in the page's own background color, punched
      // through the card's left/right edges at mid-height — the same
      // trick a real ticket stub's perforation notches use, without
      // needing to clip the card's own shape (which would also clip,
      // and square off, its shadow).
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          const Positioned(top: 0, bottom: 0, left: -7, child: _Punch()),
          const Positioned(top: 0, bottom: 0, right: -7, child: _Punch()),
        ],
      );
    }

    final taped = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -8,
          left: 18,
          child: Transform.rotate(
            angle: -0.12,
            child: Container(
              width: 40,
              height: 16,
              decoration: BoxDecoration(
                color: tape.withOpacity(0.85),
                boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.06), blurRadius: 2)],
              ),
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: _t,
      child: Transform.translate(
        offset: Offset(driftX, (1 - _t) * 30),
        child: Transform.scale(
          scale: 0.96 + 0.04 * _t,
          alignment: Alignment.center,
          child: taped,
        ),
      ),
    );
  }
}

class _Punch extends StatelessWidget {
  const _Punch();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
      ),
    );
  }
}
