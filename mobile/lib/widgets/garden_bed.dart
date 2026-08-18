import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'heart_rating.dart';
import 'scroll_reveal.dart';
import 'watched_preview_sheet.dart';
import '../services/app_translations.dart';

/// The Diary tab's centerpiece in the "Garden" theme — a window-box
/// planter that reads as denser and more in-bloom the more evenings
/// you've logged, the same "mood, not a data table" spirit as
/// [TicketJar]'s clothesline and [RouteBoard]'s road. This teaser never
/// draws one flower per real entry; that literalism lives one tap away,
/// in [GardenBedScreen], where every stop is grown from an actual diary
/// entry with its poster tucked into the bloom.
class GardenBox extends StatefulWidget {
  final List<DiaryEntry> entries;
  const GardenBox({super.key, required this.entries});

  @override
  State<GardenBox> createState() => _GardenBoxState();
}

class _GardenBoxState extends State<GardenBox> with SingleTickerProviderStateMixin {
  late final AnimationController _rustle;
  late final Animation<double> _sway;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rustle = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _sway = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -1.0, end: 0.6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _rustle, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _rustle.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy || widget.entries.isEmpty) return;
    setState(() => _busy = true);
    await _rustle.forward(from: 0);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: GardenBedScreen(entries: widget.entries)),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.entries.isEmpty;
    // Grows (capped at the fixed number of spots) with the real log, so
    // the box visibly fills in over weeks, without pretending it's a
    // literal one-flower-per-evening count — same restraint as the road
    // and the clothesline.
    final bloomCount = isEmpty ? 0 : math.min(2 + widget.entries.length, _spots.length);
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 178,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _sway,
                builder: (context, child) => _WindowBox(swayDeg: _sway.value, bloomCount: bloomCount),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEmpty ? 'an empty box, waiting'.tr : '${ruCount(widget.entries.length, one: 'вечер', few: 'вечера', many: 'вечеров', englishOne: 'evening', englishOther: 'evenings')}, ${'blooming'.tr}',
              style: SeenlyText.serif(italic: true, size: 19),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 12, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 5),
                Text(
                  isEmpty ? 'log one to plant the first seed' : 'walk the window box to see every one',
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single decorative planting spot in the teaser: fixed x position
/// (fraction of the box width), stem height, a little tilt for handmade
/// irregularity, and a palette index — the same "handful of fixed
/// anchors" pattern as [RouteBoard]'s `_previewPoints`.
class _Spot {
  final double x, height, tilt;
  final int colorIndex;
  const _Spot(this.x, this.height, this.tilt, this.colorIndex);
}

const List<_Spot> _spots = [
  _Spot(0.07, 46, -4, 0),
  _Spot(0.20, 76, 3, 1),
  _Spot(0.33, 30, -2, 2),
  _Spot(0.46, 86, 2, 3),
  _Spot(0.58, 56, -3, 4),
  _Spot(0.70, 32, 4, 5),
  _Spot(0.82, 80, -2, 0),
  _Spot(0.93, 62, 3, 1),
];

class _WindowBox extends StatelessWidget {
  final double swayDeg;
  final int bloomCount;
  const _WindowBox({required this.swayDeg, required this.bloomCount});

  static const List<Color> _bloomColors = [
    SeenlyPalette.accent,
    SeenlyPalette.coral,
    SeenlyPalette.mustard,
    SeenlyPalette.periwinkle,
    SeenlyPalette.pink,
    SeenlyPalette.sage,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const baseline = 48.0; // planter height + a little breathing room
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < _spots.length; i++) _stem(w, baseline, i),
            Positioned(left: 0, right: 0, bottom: 0, child: _Planter(width: w)),
          ],
        );
      },
    );
  }

  Widget _stem(double boxW, double baseline, int i) {
    final s = _spots[i];
    final blooming = i < bloomCount;
    final left = s.x * boxW;
    final angleDeg = s.tilt + swayDeg * 0.6;
    return Positioned(
      left: left - 15,
      bottom: baseline,
      child: Transform.rotate(
        angle: angleDeg * math.pi / 180,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              blooming ? _Bloom(color: _bloomColors[s.colorIndex % _bloomColors.length]) : const _Bud(),
              Container(
                width: 3,
                height: s.height,
                decoration: BoxDecoration(color: SeenlyPalette.sage, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A little six-petal flower, purely decorative — same shape language
/// [GardenBedScreen] uses for the frame around each real poster.
class _Bloom extends StatelessWidget {
  final Color color;
  const _Bloom({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int p = 0; p < 6; p++)
            Transform.rotate(
              angle: p * (math.pi * 2 / 6),
              child: Transform.translate(
                offset: const Offset(0, -8),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(color: color.withOpacity(0.92), shape: BoxShape.circle),
                ),
              ),
            ),
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFF0DFA0), shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

/// A closed bud — the "not blooming yet" state, on its way but not
/// there, same as the teaser's shape in the reference mock.
class _Bud extends StatelessWidget {
  const _Bud();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 13,
      decoration: const BoxDecoration(
        color: SeenlyPalette.sage,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(9),
          topRight: Radius.circular(9),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(5),
        ),
      ),
    );
  }
}

class _Planter extends StatelessWidget {
  final double width;
  const _Planter({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SeenlyPalette.mustard, Color(0xFFB9863C)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 4))],
      ),
      child: CustomPaint(painter: _SoilPainter()),
    );
  }
}

class _SoilPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // A fixed seed so the texture doesn't jitter on every rebuild — this
    // is decoration, not something that should visibly "reroll".
    final rnd = math.Random(7);
    final paint = Paint()..color = SeenlyPalette.ink.withOpacity(0.28);
    for (int i = 0; i < 30; i++) {
      canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * 6 + 3), 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoilPainter oldDelegate) => false;
}

/// The full garden: every logged evening printed as a small planted
/// card instead of a literal flower-and-stem illustration — the
/// poster framed like a little photo, a bloom badge tinted by the
/// rating tucked over its top corner, and mood tags growing beside it
/// like sprigs. Cards stack straight down the page, slightly
/// overlapping like a bed planted close together — the same "cozy
/// stack" language as [EveningRoadScreen]'s stops. Tapping one opens
/// the same soft watched-preview card as before.
class GardenBedScreen extends StatelessWidget {
  final List<DiaryEntry> entries;
  const GardenBedScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8F2E8), SeenlyPalette.background],
            stops: [0.0, 0.35],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('the window garden'.tr, style: SeenlyText.serif(italic: true, size: 18)),
                        Text(
                          entries.isEmpty
                              ? 'nothing planted yet'.tr
                              : '${ruCount(entries.length, one: 'вечер', few: 'вечера', many: 'вечеров', englishOne: 'evening', englishOther: 'evenings')} ${'grown'.tr}',
                          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                            color: SeenlyPalette.paper, shape: BoxShape.circle, boxShadow: SeenlyPalette.softShadow),
                        child: const Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'log an evening to plant the first flower'.tr,
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.inkMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 60),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _BloomCard(entry: entries[i], index: i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _bloomMonths = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _bloomDateLabel(DateTime d) => '${d.day} ${_bloomMonths[d.month - 1]}';

IconData _bloomMediaIcon(String mediaType) {
  switch (mediaType) {
    case 'movie':
      return Icons.local_movies_outlined;
    case 'series':
    case 'anime':
      return Icons.live_tv_outlined;
    case 'game':
      return Icons.sports_esports_outlined;
    case 'book':
    case 'manga':
      return Icons.menu_book_outlined;
    default:
      return Icons.movie_creation_outlined;
  }
}

/// One evening, planted like a small potted card instead of a literal
/// flower-and-stem illustration: the poster framed like a little
/// photo, a bloom badge tinted by the rating peeking over its top
/// corner, and any mood tags growing alongside it like sprigs. Mirrors
/// [EveningRoadScreen]'s `_StopTicketCard` beat for beat — same header,
/// same soft overlap as the cards stack — so the two themes feel like
/// the same app in different clothes.
class _BloomCard extends StatelessWidget {
  final DiaryEntry entry;
  final int index;
  const _BloomCard({required this.entry, required this.index});

  @override
  Widget build(BuildContext context) {
    final bloomColor = SeenlyPalette.ratingColor(entry.rating);
    final statusColor = entry.isRewatch ? SeenlyPalette.mustard : SeenlyPalette.sage;
    final statusLabel = entry.isRewatch ? 'REBLOOMED' : 'BLOOMED';
    // A hair of tilt, alternating by index, so a card doesn't look
    // machine-stamped — same trick the diary's scrapbook entries use.
    final angle = (index.isEven ? -1 : 1) * 0.012;

    return ScrollRevealEntrance(
      index: index,
      child: Transform.rotate(
        angle: angle,
        child: Transform.translate(
          // A slight overlap instead of a clean gap, same trick as the
          // train theme's stops — each card rides just over the bottom
          // edge of the one above it. Paint-only shift (Padding/margin
          // reject negative values), growing with index so every
          // consecutive pair still overlaps by ~12px.
          offset: Offset(0, -12.0 * index),
          child: GestureDetector(
            onTap: () => _openBloom(context, entry),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(20),
                boxShadow: SeenlyPalette.softShadow,
                border: Border.all(color: SeenlyPalette.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date on the left, a soft "bloomed" stamp on the
                  // right — the same beat as the train theme's ticket.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 10.5, color: SeenlyPalette.inkFaint),
                          const SizedBox(width: 5),
                          Text(_bloomDateLabel(entry.watchedAt),
                              style: SeenlyText.mono(
                                  size: 10.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(statusLabel,
                            style: SeenlyText.mono(size: 9, color: statusColor, weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  // The poster, framed and badged, with the title and
                  // its little sprigs of mood alongside it.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _framedPoster(entry, bloomColor),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SeenlyText.serif(size: 15, italic: true, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.isRewatch ? 'rewatch · ${entry.mediaType}' : entry.mediaType,
                              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                            ),
                            const SizedBox(height: 9),
                            if (entry.rating != null && entry.rating! > 0)
                              HeartRating(value: entry.rating!, size: 12)
                            else
                              Text('not yet rated'.tr,
                                  style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder)),
                            if (entry.moodTags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: [for (final tag in entry.moodTags.take(3)) _sprigTag(tag)],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _framedPoster(DiaryEntry entry, Color bloomColor) {
    return SizedBox(
      width: 56,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 80,
              child: entry.posterUrl != null && entry.posterUrl!.isNotEmpty
                  ? Image.network(entry.posterUrl!,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => _posterFallback(entry))
                  : _posterFallback(entry),
            ),
          ),
          // A tiny bloom peeking over the poster's top corner, tinted by
          // the rating — the garden theme's answer to the train theme's
          // status stamp, small enough to never compete with the poster.
          Positioned(top: -6, left: -6, child: _miniBloom(bloomColor)),
        ],
      ),
    );
  }

  Widget _miniBloom(Color color) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int p = 0; p < 5; p++)
            Transform.rotate(
              angle: p * (math.pi * 2 / 5),
              child: Transform.translate(
                offset: const Offset(0, -5.5),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: SeenlyPalette.paper, width: 1.2),
                  ),
                ),
              ),
            ),
          Container(
              width: 5, height: 5, decoration: const BoxDecoration(color: Color(0xFFF0DFA0), shape: BoxShape.circle)),
        ],
      ),
    );
  }

  Widget _sprigTag(String tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: SeenlyPalette.sage.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tag, style: SeenlyText.mono(size: 9, color: SeenlyPalette.sage)),
      );

  Widget _posterFallback(DiaryEntry entry) => Container(
        color: SeenlyPalette.mediaColor(entry.mediaType),
        alignment: Alignment.center,
        child: Icon(_bloomMediaIcon(entry.mediaType), size: 17, color: SeenlyPalette.paper),
      );

  void _openBloom(BuildContext context, DiaryEntry entry) {
    showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
  }
}
