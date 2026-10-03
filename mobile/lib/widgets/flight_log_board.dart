import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'heart_rating.dart';
import 'scroll_reveal.dart';
import 'watched_preview_sheet.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// The Diary tab's centerpiece in the "shuttle" theme — a small patch
/// of night sky that fills in with stars as evenings get logged, then
/// draws faint lines between them into a personal constellation. Same
/// "mood, not a data table" spirit as [TicketJar]'s clothesline,
/// [RouteBoard]'s road, and [GardenBox]'s window planter. This teaser
/// never lights one star per real entry; that literalism lives one tap
/// away, in [FlightLogScreen], where every stop is a real diary entry
/// with its poster tucked into the card.
class FlightLogBoard extends StatefulWidget {
  final List<DiaryEntry> entries;
  const FlightLogBoard({super.key, required this.entries});

  @override
  State<FlightLogBoard> createState() => _FlightLogBoardState();
}

class _FlightLogBoardState extends State<FlightLogBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy || widget.entries.isEmpty) return;
    setState(() => _busy = true);
    await _pulse.forward(from: 0);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: FlightLogScreen(entries: widget.entries)),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.entries.isEmpty;
    // Grows (capped at the fixed number of stars) with the real log,
    // so the sky visibly fills in over weeks, without pretending it's
    // a literal one-star-per-evening count — same restraint as the
    // road and the clothesline.
    final litCount = isEmpty ? 0 : math.min(2 + widget.entries.length, _stars.length);
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: ClayBoxDecoration(
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
                animation: _pulse,
                builder: (context, child) => _NightSky(pulse: _pulse.value, litCount: litCount),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEmpty
                  ? 'an empty sky, waiting'.tr
                  : '${nCount('nEvenings', widget.entries.length)}, ${'charted'.tr}',
              style: SeenlyText.serif(italic: true, size: 19),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 12, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 5),
                Text(
                  isEmpty ? 'log one to light the first star'.tr : 'trace the sky to see every one'.tr,
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

/// A single fixed star position in the teaser sky (fraction of the
/// box's width/height), a size, and a palette index — the same
/// "handful of fixed anchors" pattern as [RouteBoard]'s
/// `_previewPoints` and [GardenBox]'s `_spots`.
class _Star {
  final double x, y, size;
  final int colorIndex;
  const _Star(this.x, this.y, this.size, this.colorIndex);
}

const List<_Star> _stars = [
  _Star(0.08, 0.60, 3.5, 0),
  _Star(0.18, 0.24, 2.5, 1),
  _Star(0.30, 0.72, 4.0, 2),
  _Star(0.40, 0.15, 2.5, 3),
  _Star(0.50, 0.48, 3.5, 4),
  _Star(0.60, 0.80, 2.5, 5),
  _Star(0.70, 0.30, 4.0, 0),
  _Star(0.80, 0.62, 2.5, 1),
  _Star(0.90, 0.20, 3.5, 2),
  _Star(0.95, 0.68, 2.5, 3),
];

class _NightSky extends StatelessWidget {
  final double pulse;
  final int litCount;
  const _NightSky({required this.pulse, required this.litCount});

  static final List<Color> _starColors = [
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
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _SkyPainter(litCount: litCount, pulse: pulse, colors: _starColors),
        );
      },
    );
  }
}

class _SkyPainter extends CustomPainter {
  final int litCount;
  final double pulse;
  final List<Color> colors;
  _SkyPainter({required this.litCount, required this.pulse, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // The night backdrop, deep and quiet — same rounded-rect language
    // as the garden theme's planter box.
    final bgPaint = Paint()..color = const Color(0xFF171A2E);
    final bgRect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(bgRect, bgPaint);

    // Faint constellation lines between lit stars, oldest to newest —
    // this is the one visual idea unique to this theme: each evening
    // doesn't just add a star, it extends a path across the sky.
    if (litCount > 1) {
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.14)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < litCount - 1 && i < _stars.length - 1; i++) {
        final a = _stars[i];
        final b = _stars[i + 1];
        canvas.drawLine(
          Offset(a.x * size.width, a.y * size.height),
          Offset(b.x * size.width, b.y * size.height),
          linePaint,
        );
      }
    }

    for (int i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final lit = i < litCount;
      final justLit = lit && i == litCount - 1;
      final scale = justLit ? (1.0 + pulse * 0.9) : 1.0;
      final center = Offset(s.x * size.width, s.y * size.height);
      final color = lit ? colors[s.colorIndex % colors.length] : Colors.white.withOpacity(0.18);
      final radius = (s.size + 1.5) * scale;

      if (lit) {
        // A soft glow behind every lit star — the sky's answer to the
        // garden's tiny bloom badge.
        final glowPaint = Paint()
          ..color = color.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(center, radius * 2.2, glowPaint);
      }
      canvas.drawCircle(center, radius, Paint()..color = lit ? color : Colors.white.withOpacity(0.25));
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) =>
      oldDelegate.litCount != litCount || oldDelegate.pulse != pulse;
}

/// The full-screen list behind the teaser — every real diary entry,
/// posed as a launch record instead of a literal per-star illustration.
class FlightLogScreen extends StatelessWidget {
  final List<DiaryEntry> entries;
  const FlightLogScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF171A2E), SeenlyPalette.background],
            stops: const [0.0, 0.35],
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
                        Text('the flight log'.tr,
                            style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)),
                        Text(
                          entries.isEmpty
                              ? 'nothing launched yet'.tr
                              : '${nCount('nEvenings', entries.length)} ${'logged'.tr}',
                          style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.6)),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: ClayBoxDecoration(
                            color: SeenlyPalette.paper, shape: BoxShape.circle, boxShadow: SeenlyPalette.softShadow),
                        child: Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'log an evening to light the first star'.tr,
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.paper.withOpacity(0.7)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 60),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _LaunchCard(entry: entries[i], index: i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _launchMonths = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _launchDateLabel(DateTime d) => '${d.day} ${_launchMonths[d.month - 1]}';

IconData _launchMediaIcon(String mediaType) {
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

/// One evening, posed like a small launch record instead of a literal
/// star illustration: the poster framed like a viewport, with the
/// title and its little tags of mood alongside it. Mirrors
/// [_BloomCard] in garden_bed.dart and the train theme's ticket card.
class _LaunchCard extends StatelessWidget {
  final DiaryEntry entry;
  final int index;
  const _LaunchCard({required this.entry, required this.index});

  @override
  Widget build(BuildContext context) {
    final starColor = SeenlyPalette.ratingColor(entry.rating);
    final statusColor = entry.isRewatch ? SeenlyPalette.mustard : SeenlyPalette.periwinkle;
    final statusLabel = entry.isRewatch ? 'RELAUNCHED' : 'LAUNCHED';
    // A hair of tilt, alternating by index, so a card doesn't look
    // machine-stamped — same trick the diary's scrapbook entries use.
    final angle = (index.isEven ? -1 : 1) * 0.012;

    return ScrollRevealEntrance(
      index: index,
      child: Transform.rotate(
        angle: angle,
        child: Transform.translate(
          // A slight overlap instead of a clean gap, same trick as the
          // train theme's stops and the garden's blooms.
          offset: Offset(0, -12.0 * index),
          child: GestureDetector(
            onTap: () => _openLaunch(context, entry),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(20),
                boxShadow: SeenlyPalette.softShadow,
                border: Border.all(color: SeenlyPalette.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date on the left, a soft "launched" stamp on the
                  // right — the same beat as the train theme's ticket.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 10.5, color: SeenlyPalette.inkFaint),
                          const SizedBox(width: 5),
                          Text(_launchDateLabel(entry.watchedAt),
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
                  // The poster, framed like a viewport and badged, with
                  // the title and its little tags of mood alongside it.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _framedPoster(entry, starColor),
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
                                children: [for (final tag in entry.moodTags.take(3)) _tagChip(tag)],
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

  Widget _framedPoster(DiaryEntry entry, Color starColor) {
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
          // A tiny star peeking over the poster's top corner, tinted by
          // the rating — this theme's answer to the garden's mini
          // bloom and the train theme's status stamp, small enough to
          // never compete with the poster.
          Positioned(top: -6, left: -6, child: _miniStar(starColor)),
        ],
      ),
    );
  }

  Widget _miniStar(Color color) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int p = 0; p < 4; p++)
            Transform.rotate(
              angle: p * (math.pi / 4) + math.pi / 4,
              child: Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: SeenlyPalette.paper, width: 1.2)),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(String tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: SeenlyPalette.periwinkle.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tag, style: SeenlyText.mono(size: 9, color: SeenlyPalette.periwinkle)),
      );

  Widget _posterFallback(DiaryEntry entry) => Container(
        color: SeenlyPalette.mediaColor(entry.mediaType),
        alignment: Alignment.center,
        child: Icon(_launchMediaIcon(entry.mediaType), size: 17, color: SeenlyPalette.paper),
      );

  void _openLaunch(BuildContext context, DiaryEntry entry) {
    showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
  }
}
