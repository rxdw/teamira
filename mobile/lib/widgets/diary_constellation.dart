import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'series_episodes_sheet.dart';
import 'watched_preview_sheet.dart';
import 'wow_motion.dart' show PressScale, FadeInNetworkImage;
import '../services/app_translations.dart' show TrString, ruCount;

/// One star per logged evening: brighter and bigger for a higher rating,
/// a quiet dim speck for an unrated one — so the shape of a life on
/// screen reads at a glance before a single title is read. Position is
/// derived from the entry's own id (see [_layoutFor]), not randomized on
/// every rebuild, so a star stays put between frames, between the panel
/// and the fullscreen view, and after a pull-to-refresh reorders the
/// underlying list.
class _StarLayout {
  final DiaryEntry entry;
  final Offset unit; // 0..1 within the field, independent of pixel size
  final double sizeFactor; // 0..1, drives radius + glow
  const _StarLayout(this.entry, this.unit, this.sizeFactor);
}

List<_StarLayout> _layoutFor(List<DiaryEntry> entries) {
  final out = <_StarLayout>[];
  for (final e in entries) {
    // A cheap, stable hash-based scatter — good enough for a decorative
    // sky, and deterministic so the same entry always lands in the same
    // spot rather than reshuffling every time this list is rebuilt.
    //
    // Deliberately NOT splitting `id.hashCode`'s low/high bits into x/y:
    // Dart's default String.hashCode doesn't guarantee entropy spread
    // evenly across all 32 bits for short id-like strings (in practice
    // the upper bits came out near-zero for most real ids, which is
    // what pinned every star to the top of the sky). `_mixedHash` runs
    // its own avalanche mix per call, and x/y each get a different salt
    // so they vary independently instead of being correlated slices of
    // the same number.
    final rx = _mixedHash(e.id, 1) / 0xFFFFFFFF;
    final ry = _mixedHash(e.id, 2) / 0xFFFFFFFF;
    // Keep stars off the very edges so glow never clips against the
    // panel's rounded corners.
    final ux = 0.08 + rx * 0.84;
    final uy = 0.08 + ry * 0.84;
    final rating = e.rating;
    final sizeFactor = rating == null ? 0.28 : (0.4 + (rating / 10) * 0.6);
    out.add(_StarLayout(e, Offset(ux, uy), sizeFactor.clamp(0.0, 1.0)));
  }
  return out;
}

/// A small, well-mixed 32-bit hash (FNV-1a + a Murmur-style avalanche
/// finish) over a string plus a salt — used instead of the built-in
/// `String.hashCode` specifically because that one isn't guaranteed to
/// spread bits evenly across its whole range for short inputs, which is
/// exactly what a scatter layout needs. Same string + same salt always
/// gives the same value.
///
/// Multiplies through [_mul32] rather than plain `*` — on the Dart VM
/// ints are 64-bit so a 32-bit-by-32-bit multiply is harmless, but
/// compiled to JS (web) numbers only carry 53 safe integer bits, and
/// this project ships a web target too. [_mul32] keeps every
/// intermediate value well under that ceiling so the hash comes out
/// identical on every platform.
int _mixedHash(String s, int salt) {
  var h = 0x811c9dc5 ^ salt;
  for (final unit in s.codeUnits) {
    h = (h ^ unit) & 0xFFFFFFFF;
    h = _mul32(h, 0x01000193);
  }
  h ^= h >> 16;
  h = _mul32(h, 0x85ebca6b);
  h ^= h >> 13;
  h = _mul32(h, 0xc2b2ae35);
  h ^= h >> 16;
  return h & 0xFFFFFFFF;
}

/// 32-bit-wrapping multiply done as four 16-bit partial products, so no
/// intermediate value exceeds ~2^32 — see [_mixedHash]'s doc comment for
/// why that matters on web.
int _mul32(int a, int b) {
  final al = a & 0xFFFF, ah = (a >> 16) & 0xFFFF;
  final bl = b & 0xFFFF, bh = (b >> 16) & 0xFFFF;
  final low = al * bl;
  final mid = (al * bh + ah * bl) & 0xFFFF;
  return (low + (mid << 16)) & 0xFFFFFFFF;
}

/// A handful of tiny, non-interactive background stars purely for
/// atmosphere — filling out the sky around the "real" stars (one per
/// diary entry) so a short diary doesn't look like a nearly-empty void.
/// Seeded once per painter instance rather than per frame.
List<Offset> _fillerStars(int count, int seed) {
  final rnd = math.Random(seed);
  return List.generate(count, (_) => Offset(rnd.nextDouble(), rnd.nextDouble()));
}

class _StarFieldPainter extends CustomPainter {
  final List<_StarLayout> stars;
  final List<Offset> filler;
  final String? selectedId;
  final double twinkle; // 0..1, loops — see the AnimationController below

  _StarFieldPainter({
    required this.stars,
    required this.filler,
    required this.selectedId,
    required this.twinkle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillerPaint = Paint()..color = Colors.white.withOpacity(0.22);
    for (final f in filler) {
      final p = Offset(f.dx * size.width, f.dy * size.height);
      canvas.drawCircle(p, 0.9, fillerPaint);
    }

    for (final s in stars) {
      final center = Offset(s.unit.dx * size.width, s.unit.dy * size.height);
      final isSelected = s.entry.id == selectedId;
      final baseRadius = 2.2 + s.sizeFactor * 3.4;
      // A slow shared pulse (see `twinkle`) nudges brightness up and down
      // a little per-star, offset by each star's own hash so the whole
      // sky doesn't breathe in lockstep.
      final phase = (_mixedHash(s.entry.id, 3) % 628) / 100.0;
      final pulse = 0.75 + 0.25 * (math.sin(twinkle * 2 * math.pi + phase) * 0.5 + 0.5);
      final color = SeenlyPalette.ratingColor(s.entry.rating);
      final glowColor = Color.lerp(color, Colors.white, 0.35)!;

      final radius = isSelected ? baseRadius * 1.35 : baseRadius * pulse;

      // Soft glow halo, then a crisp bright core — the same two-layer
      // trick [LightBloom] uses elsewhere, kept local here since this
      // needs per-star color and per-star pulse.
      final glowPaint = Paint()
        ..color = glowColor.withOpacity(isSelected ? 0.55 : 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.8);
      canvas.drawCircle(center, radius * 2.2, glowPaint);

      final corePaint = Paint()..color = glowColor.withOpacity(0.95);
      canvas.drawCircle(center, radius, corePaint);

      if (isSelected) {
        final ringPaint = Paint()
          ..color = glowColor.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        canvas.drawCircle(center, radius + 6, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) =>
      oldDelegate.stars != stars ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.twinkle != twinkle;
}

/// The interactive sky itself — shared by the diary panel and the
/// fullscreen view below, so both hit-test and render the exact same
/// stars. Tapping near a star selects it (showing the vertical ticket);
/// tapping empty sky clears the selection; [onExpand], if given, fires
/// on a tap that lands on empty sky, so the compact panel can use it to
/// grow into the fullscreen view without stealing star taps.
///
/// Sizing has two modes: leave [canvasSize] null and this fills
/// whatever space its parent gives it (the compact panel embedded in
/// the diary list). Pass an explicit [canvasSize] and it renders at
/// exactly that size regardless of the parent's constraints — used by
/// [ConstellationFullScreen], which deliberately makes that size bigger
/// than the screen (see that class) and wraps this in an
/// [InteractiveViewer] so there's real room to pan into rather than
/// panning just bouncing off the screen's own edges.
class ConstellationSky extends StatefulWidget {
  final List<DiaryEntry> entries;
  final VoidCallback? onExpand;
  final bool compact;
  final Size? canvasSize;

  const ConstellationSky({
    super.key,
    required this.entries,
    this.onExpand,
    this.compact = false,
    this.canvasSize,
  });

  @override
  State<ConstellationSky> createState() => _ConstellationSkyState();
}

class _ConstellationSkyState extends State<ConstellationSky>
    with SingleTickerProviderStateMixin {
  late final AnimationController _twinkleController;
  late List<_StarLayout> _stars;
  late List<Offset> _filler;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _stars = _layoutFor(widget.entries);
    _filler = _fillerStars(46, widget.entries.length);
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant ConstellationSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _stars = _layoutFor(widget.entries);
      _filler = _fillerStars(46, widget.entries.length);
      // A refresh can drop or reorder entries out from under an open
      // ticket popup — if the selected star no longer exists, clear the
      // selection instead of leaving `_selected` pointing at nothing.
      if (_selectedId != null && !_stars.any((s) => s.entry.id == _selectedId)) {
        _selectedId = null;
      }
    }
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    super.dispose();
  }

  _StarLayout? _hitTest(Offset local, Size size) {
    _StarLayout? best;
    double bestDist = double.infinity;
    for (final s in _stars) {
      final center = Offset(s.unit.dx * size.width, s.unit.dy * size.height);
      final d = (center - local).distance;
      // Generous hit radius — a bright point on a phone screen is a
      // small target, so this is closer to "tapped roughly this star"
      // than a pixel-exact hit test.
      if (d < 26 && d < bestDist) {
        best = s;
        bestDist = d;
      }
    }
    return best;
  }

  void _handleTap(Offset local, Size size) {
    final hit = _hitTest(local, size);
    if (hit != null) {
      setState(() => _selectedId = hit.entry.id);
      return;
    }
    if (_selectedId != null) {
      setState(() => _selectedId = null);
      return;
    }
    widget.onExpand?.call();
  }

  _StarLayout? get _selected {
    if (_selectedId == null) return null;
    for (final s in _stars) {
      if (s.entry.id == _selectedId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canvasSize != null) {
      return _buildField(context, widget.canvasSize!);
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildField(context, Size(constraints.maxWidth, constraints.maxHeight)),
    );
  }

  Widget _buildField(BuildContext context, Size size) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleTap(d.localPosition, size),
            child: AnimatedBuilder(
              animation: _twinkleController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _StarFieldPainter(
                    stars: _stars,
                    filler: _filler,
                    selectedId: _selectedId,
                    twinkle: _twinkleController.value,
                  ),
                );
              },
            ),
          ),
          if (_selected != null)
            _StarTicketPopup(
              key: ValueKey(_selected!.entry.id),
              star: _selected!,
              fieldSize: size,
              onDismiss: () => setState(() => _selectedId = null),
              onOpen: () {
                final entry = _selected!.entry;
                setState(() => _selectedId = null);
                // A series entry is one persistent row for the whole
                // watch, not one evening — same split diary_screen's
                // own rows make between `_DiaryRow` and
                // `_SeriesEntryRow`.
                if (entry.season != null) {
                  showSeriesEpisodesSheet(
                    context,
                    mediaId: entry.mediaId,
                    source: entry.source,
                    title: entry.displayTitle,
                    mediaType: entry.mediaType,
                    posterUrl: entry.posterUrl,
                  );
                } else {
                  showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
                }
              },
            ),
        ],
      ),
    );
  }
}

/// The "vertical ticket with a poster" that pops up next to a tapped
/// star — a stub-and-body cinema ticket turned portrait, poster filling
/// the body, torn apart along a jagged seam by [_TearableTicket] below.
/// A plain tap hands off to the existing watched-preview sheet (rating,
/// review, mood tags — and from there, the poster opens the full title
/// screen); this widget only owns the reveal moment and positioning.
class _StarTicketPopup extends StatelessWidget {
  final _StarLayout star;
  final Size fieldSize;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  const _StarTicketPopup({
    super.key,
    required this.star,
    required this.fieldSize,
    required this.onDismiss,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 140.0;
    const cardHeight = 236.0;
    final anchor = Offset(star.unit.dx * fieldSize.width, star.unit.dy * fieldSize.height);
    // Keep the card on-screen: flip above the star if it's in the lower
    // half of the field, and clamp horizontally within the field bounds.
    final showBelow = star.unit.dy < 0.55;
    var left = anchor.dx - cardWidth / 2;
    left = left.clamp(6.0, math.max(6.0, fieldSize.width - cardWidth - 6));
    final top = showBelow ? anchor.dy + 18 : anchor.dy - cardHeight - 18;

    return Stack(
      children: [
        // Tapping anywhere else in the sky dismisses — the sky's own
        // GestureDetector already clears selection on an empty-sky tap,
        // this just widens that to "anywhere behind the card".
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top.clamp(4.0, math.max(4.0, fieldSize.height - cardHeight - 4)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Transform.scale(
              scale: 0.7 + 0.3 * t,
              alignment: showBelow ? Alignment.topCenter : Alignment.bottomCenter,
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            ),
            child: _TearableTicket(
              entry: star.entry,
              width: cardWidth,
              height: cardHeight,
              onOpen: onOpen,
            ),
          ),
        ),
      ],
    );
  }
}

/// The vertical ticket itself — a real cinema-stub shape (rounded outer
/// corners, a jagged torn seam between poster and stub, small punched
/// notches at the seam) rather than a plain rounded card. Drag the stub
/// down and it peels away from the poster along that seam, wobbling the
/// way real paper does; let go before it fully separates and it springs
/// back. Pull far enough and it does tear all the way through — both
/// halves swing apart for a beat — but that's purely a fidget: nothing
/// is confirmed, saved, or navigated by it, and it eases itself back
/// together on its own right after. A plain tap (not a drag) still
/// calls [onOpen], same as before.
class _TearableTicket extends StatefulWidget {
  final DiaryEntry entry;
  final double width;
  final double height;
  final VoidCallback onOpen;

  const _TearableTicket({
    required this.entry,
    required this.width,
    required this.height,
    required this.onOpen,
  });

  @override
  State<_TearableTicket> createState() => _TearableTicketState();
}

class _TearableTicketState extends State<_TearableTicket> with TickerProviderStateMixin {
  static const double _stubHeight = 46;
  static const double _maxPullPx = 30;
  static const double _tearThreshold = 0.65;
  static const int _seed = 4127;

  late final AnimationController _springCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 460))
        ..addListener(() {
          if (_spring != null) setState(() => _pull = _spring!.value);
        });
  Animation<double>? _spring;

  late final AnimationController _flyCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  double _pull = 0; // 0..1 while actively dragging or springing back
  bool _tearing = false; // true only during the full-tear flourish
  bool _pressed = false;

  @override
  void dispose() {
    _springCtrl.dispose();
    _flyCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    if (_tearing) return;
    _springCtrl.stop();
    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_tearing) return;
    setState(() => _pull = (_pull + d.delta.dy / _maxPullPx).clamp(0.0, 1.0));
  }

  void _onDragEnd(DragEndDetails _) {
    if (_tearing) return;
    if (_pull >= _tearThreshold) {
      _playTear();
    } else {
      _spring = Tween<double>(begin: _pull, end: 0)
          .animate(CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut));
      _springCtrl.forward(from: 0);
    }
  }

  Future<void> _playTear() async {
    HapticFeedback.mediumImpact();
    setState(() => _tearing = true);
    await _flyCtrl.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _tearing = false;
      _pull = 0;
    });
    _flyCtrl.value = 0;
  }

  /// Pull "amount" during the full-tear flourish, in [_maxPullPx] units
  /// (can run past 1.0 — the halves genuinely separate further than a
  /// drag alone would take them): swings out, holds a beat, eases back
  /// to fully whole. Always lands back at 0 — a rip, not a reveal, so
  /// there's nothing left over for anything else to react to.
  double _flyPull(double t) {
    if (t < 0.4) return Curves.easeOutCubic.transform(t / 0.4) * 1.7;
    if (t < 0.55) return 1.7;
    return 1.7 * (1 - Curves.easeInOutCubic.transform((t - 0.55) / 0.45));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flyCtrl,
      builder: (context, _) {
        final pull = _tearing ? _flyPull(_flyCtrl.value) : _pull;
        final gap = pull * _maxPullPx;
        final rot = pull * 0.11;
        final posterHeight = widget.height - _stubHeight;
        const notchRadius = 5.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onOpen,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: -gap * 0.16,
                    width: widget.width,
                    height: posterHeight,
                    child: Transform.rotate(
                      angle: -rot * 0.35,
                      alignment: Alignment.bottomCenter,
                      child: _TicketPiece(
                        isTop: true,
                        seed: _seed,
                        notchRadius: notchRadius,
                        child: _TicketPosterFace(entry: widget.entry),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: posterHeight + gap,
                    width: widget.width,
                    height: _stubHeight,
                    child: Transform.rotate(
                      angle: rot,
                      alignment: Alignment.topCenter,
                      child: _TicketPiece(
                        isTop: false,
                        seed: _seed,
                        notchRadius: notchRadius,
                        child: _TicketStubFace(entry: widget.entry),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One clipped, shadowed half of the torn ticket — rounded on its outer
/// corners, a small punched notch at the seam, and a ragged inner edge
/// where it tears from the other half. Shares its exact silhouette
/// between the drop shadow and the clip (see [_TicketHalfClipperV]) so
/// the shadow follows the torn edge instead of falling back to a plain
/// rectangle.
class _TicketPiece extends StatelessWidget {
  final bool isTop;
  final int seed;
  final double notchRadius;
  final Widget child;

  const _TicketPiece({
    required this.isTop,
    required this.seed,
    required this.notchRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _TicketPieceShadow(isTop: isTop, seed: seed, notchRadius: notchRadius),
          ),
        ),
        ClipPath(
          clipper: _TicketHalfClipperV(isTop: isTop, seed: seed, notchRadius: notchRadius),
          child: Container(color: SeenlyPalette.paper, child: child),
        ),
      ],
    );
  }
}

class _TicketPieceShadow extends CustomPainter {
  final bool isTop;
  final int seed;
  final double notchRadius;
  const _TicketPieceShadow({required this.isTop, required this.seed, required this.notchRadius});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final clipper = _TicketHalfClipperV(isTop: isTop, seed: seed, notchRadius: notchRadius);
    canvas.drawShadow(clipper.getClip(size), Colors.black.withOpacity(0.4), 6, false);
  }

  @override
  bool shouldRepaint(covariant _TicketPieceShadow oldDelegate) => false;
}

/// The jagged seam shared by both halves of a torn ticket — the same
/// idea as `_raggedSeam` in tear_ticket_confirm.dart, just turned 90°:
/// that one splits a card left/right (teeth stepping down its height,
/// jag in x), this one splits it top/bottom (teeth stepping across its
/// width, jag in y) to match this ticket's own poster-over-stub shape.
/// Both halves are cut from the same [seed], so the teeth on one side
/// always sit in the notches of the other.
Path _raggedSeamV(Size size, {required bool edgeOnBottom, required int seed}) {
  const teeth = 9;
  const amplitude = 4.2;
  final rnd = math.Random(seed);
  final offsets = List<double>.generate(teeth + 1, (i) {
    if (i == 0 || i == teeth) return 0.0; // corners stay flush with the card
    return (rnd.nextDouble() * 2 - 1) * amplitude;
  });
  final stepW = size.width / teeth;

  final zigzag = Path();
  if (edgeOnBottom) {
    zigzag.moveTo(-10, 0);
    zigzag.lineTo(-10, size.height);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(i * stepW, size.height + offsets[i]);
    }
    zigzag.lineTo(size.width + 10, 0);
    zigzag.close();
  } else {
    zigzag.moveTo(-10, size.height + 10);
    for (var i = 0; i <= teeth; i++) {
      zigzag.lineTo(i * stepW, offsets[i]);
    }
    zigzag.lineTo(size.width + 10, size.height + 10);
    zigzag.close();
  }
  return zigzag;
}

class _TicketHalfClipperV extends CustomClipper<Path> {
  final bool isTop;
  final int seed;
  final double notchRadius;
  const _TicketHalfClipperV({required this.isTop, required this.seed, required this.notchRadius});

  @override
  Path getClip(Size size) {
    final rrect = isTop
        ? RRect.fromRectAndCorners(
            Offset.zero & size,
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: const Radius.circular(3),
            bottomRight: const Radius.circular(3),
          )
        : RRect.fromRectAndCorners(
            Offset.zero & size,
            bottomLeft: const Radius.circular(14),
            bottomRight: const Radius.circular(14),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          );
    var base = Path()..addRRect(rrect);
    final notchY = isTop ? size.height : 0.0;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, notchY), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(size.width, notchY), radius: notchRadius));
    base = Path.combine(PathOperation.difference, base, notches);
    final ragged = _raggedSeamV(size, edgeOnBottom: isTop, seed: seed);
    return Path.combine(PathOperation.intersect, base, ragged);
  }

  @override
  bool shouldReclip(covariant _TicketHalfClipperV oldDelegate) => true;
}

/// The poster half's face: the poster image (or a flat title-on-color
/// fallback) filling the piece, with the watched date banded across the
/// top — unchanged from the original ticket's poster area, just pulled
/// out into its own widget so [_TearableTicket] can clip and shadow it
/// independently of the stub below.
class _TicketPosterFace extends StatelessWidget {
  final DiaryEntry entry;
  const _TicketPosterFace({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.ratingColor(entry.rating);
    return Stack(
      fit: StackFit.expand,
      children: [
        (entry.posterUrl != null && entry.posterUrl!.isNotEmpty)
            ? FadeInNetworkImage(
                url: entry.posterUrl!,
                fit: BoxFit.cover,
                placeholder: Container(color: color.withOpacity(0.3)),
              )
            : Container(
                color: color.withOpacity(0.3),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: Text(
                  entry.displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(size: 12, color: SeenlyPalette.ink),
                ),
              ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            color: Colors.black.withOpacity(0.28),
            alignment: Alignment.center,
            child: Text(
              _dateLabel(entry.watchedAt),
              style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.paper),
            ),
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

/// The stub half's face: title + heart rating, same as the original
/// ticket's stub row — pulled out for the same reason as
/// [_TicketPosterFace] above.
class _TicketStubFace extends StatelessWidget {
  final DiaryEntry entry;
  const _TicketStubFace({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.ratingColor(entry.rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            entry.displayTitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(size: 11.5, color: SeenlyPalette.ink),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite, size: 9, color: color),
              const SizedBox(width: 3),
              Text(
                entry.rating != null ? '${entry.rating}/10' : '—',
                style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The night-sky gradient behind every constellation view. Was
/// previously mixed from the app's own warm `ink`/`accent` tones to
/// stay "in family" — but that read as a lit room, not a sky, so this
/// is now a proper deep indigo-to-black night: dark enough that the
/// stars themselves are what's doing the work, with just a whisper of
/// the app's plum [accent] worked into the topmost stop (well short of
/// fighting star colors like `ratingColor`'s coral/mustard/sage) so it
/// doesn't read as a generic stock-photo sky either.
BoxDecoration constellationBackdrop() {
  const spaceTop = Color(0xFF171225); // near-black, faint plum cast
  const spaceMid = Color(0xFF0D0B16);
  const spaceBottom = Color(0xFF060509); // essentially black
  final accentWhisper = Color.lerp(spaceTop, SeenlyPalette.accent, 0.22)!;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [accentWhisper, spaceTop, spaceMid, spaceBottom],
      stops: const [0, 0.18, 0.55, 1],
    ),
  );
}

/// The compact panel embedded in the diary list — sky on top, a soft
/// "N evenings · tap to explore" caption pinned to the bottom edge so
/// it's clear the panel opens into something bigger. Sized by the
/// caller (see DiaryScreen: roughly 2/3 of the screen height), and the
/// rest of the diary — history, board, everything already there —
/// simply continues below it in the same scroll view.
///
/// This panel itself is *not* pannable — it's a fixed-size preview
/// living inside the diary's own scroll view, and a free-panning
/// gesture surface there would just fight the page's vertical scroll.
/// Free panning lives one tap away, in [ConstellationFullScreen].
class DiaryConstellationPanel extends StatelessWidget {
  final List<DiaryEntry> entries;
  const DiaryConstellationPanel({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: constellationBackdrop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ConstellationSky(
              entries: entries,
              compact: true,
              onExpand: () => _openFullscreen(context),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ruCount(entries.length,
                            one: 'вечер', few: 'вечера', many: 'вечеров',
                            englishOne: 'evening', englishOther: 'evenings'),
                        style: SeenlyText.mono(size: 10.5, color: Colors.white70),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('tap to explore'.tr,
                              style: SeenlyText.mono(size: 10.5, color: Colors.white70)),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_full, size: 12, color: Colors.white70),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ConstellationFullScreen(entries: entries),
        // A soft cross-fade + gentle scale-up rather than a Hero flight:
        // the fullscreen sky is a genuinely bigger canvas (see that
        // class) wrapped in its own InteractiveViewer, not the same
        // widget subtree stretched, so a literal Hero morph between the
        // two would either mismatch or force them to fake-share a tree.
        // This still reads as "the sky opens up", just via opacity/scale
        // instead of a shared-element flight.
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
          );
        },
      ),
    );
  }
}

/// The fullscreen constellation — reached by tapping the compact panel.
/// The sky here is deliberately laid out on a canvas *larger than the
/// screen* (see [_densityFactor]): the more evenings there are to
/// place, the more room the sky gets, so stars spread out into that
/// extra space instead of crowding together. [InteractiveViewer] wraps
/// it with `constrained: false` (so that bigger-than-viewport canvas is
/// honored instead of being squeezed to fit) and a practically
/// unbounded [InteractiveViewer.boundaryMargin], so panning past the
/// canvas's own edge doesn't hit a visible wall — it just keeps gliding
/// into more of the same near-black backdrop the sky itself sits on,
/// same color inside and out, so there's nothing to visibly hit.
class ConstellationFullScreen extends StatefulWidget {
  final List<DiaryEntry> entries;
  const ConstellationFullScreen({super.key, required this.entries});

  @override
  State<ConstellationFullScreen> createState() => _ConstellationFullScreenState();
}

class _ConstellationFullScreenState extends State<ConstellationFullScreen> {
  final TransformationController _controller = TransformationController();
  Size? _centeredFor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How much bigger than the viewport the pannable sky should be.
  /// Even a handful of entries gets noticeably more room than the
  /// screen itself (so there's always somewhere to pan to, not just a
  /// screen-sized box with elastic edges); a big diary keeps growing
  /// the canvas so stars spread out into that space rather than
  /// stacking on top of each other.
  double _densityFactor(int n) {
    if (n <= 18) return 1.6;
    return (math.sqrt(n / 20.0)).clamp(1.6, 3.4);
  }

  void _centerOn(Size viewport, Size canvas) {
    if (_centeredFor == viewport) return;
    _centeredFor = viewport;
    final dx = ((viewport.width - canvas.width) / 2);
    final dy = ((viewport.height - canvas.height) / 2);
    _controller.value = Matrix4.identity()..translate(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060509), // matches constellationBackdrop's own edge
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final factor = _densityFactor(widget.entries.length);
          final canvas = Size(viewport.width * factor, viewport.height * factor);
          // Center the initial view on the middle of the sky rather than
          // its top-left corner, the first time this viewport size is
          // seen — after that, leave the person's own pan/zoom alone.
          WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(viewport, canvas));
          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _controller,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.5,
                maxScale: 3.2,
                child: SizedBox(
                  width: canvas.width,
                  height: canvas.height,
                  child: DecoratedBox(
                    decoration: constellationBackdrop(),
                    child: ConstellationSky(entries: widget.entries, canvasSize: canvas),
                  ),
                ),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 8,
                      child: PressScale(
                        onTap: () => Navigator.of(context).pop(),
                        haptics: true,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 16,
                      child: Text(
                        ruCount(widget.entries.length,
                            one: 'вечер', few: 'вечера', many: 'вечеров',
                            englishOne: 'evening', englishOther: 'evenings'),
                        style: SeenlyText.mono(size: 11, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
