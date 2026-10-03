import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/coach_routes.dart';
import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'scroll_reveal.dart';
import 'watched_preview_sheet.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// The Diary tab's centerpiece in the "Evening Route" theme — a soft
/// little road curling from one evening to the next, replacing both
/// the old departures board *and* the plain day-by-day list underneath
/// it. A stop on the road is a film; tapping the card opens the whole
/// route in [EveningRoadScreen].
class RouteBoard extends StatelessWidget {
  final List<DiaryEntry> entries;
  const RouteBoard({super.key, required this.entries});

  // A handful of fixed, decorative waypoints for the teaser's little
  // preview road — this card is a mood, not a data table, so it always
  // draws the same gentle climb regardless of how many evenings exist.
  static const List<Offset> _previewPoints = [
    Offset(0.10, 0.94),
    Offset(0.30, 0.66),
    Offset(0.34, 0.50),
    Offset(0.56, 0.40),
    Offset(0.74, 0.34),
    Offset(0.92, 0.16),
  ];

  @override
  Widget build(BuildContext context) {
    final isEmpty = entries.isEmpty;
    return GestureDetector(
      onTap: isEmpty
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EveningRoadScreen(entries: entries)),
              ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _RoadPainter(
                  points: _previewPoints,
                  roadWidth: 15,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    return Stack(
                      children: [
                        for (int i = 0; i < _previewPoints.length; i++)
                          _previewDot(size, i),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isEmpty
                  ? 'an empty road, waiting'.tr
                  : '${nCount('nStops', entries.length)} ${'on the road'.tr}',
              style: SeenlyText.serif(size: 21, weight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              isEmpty
                  ? 'log an evening to lay the first stretch of road'
                  : 'trace back any evening you passed through',
              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewDot(Size size, int i) {
    final isEndpoint = i == 0 || i == _previewPoints.length - 1;
    final radius = isEndpoint ? 11.0 : 7.0;
    final color = isEndpoint ? SeenlyPalette.accent : SeenlyPalette.inkFaint.withOpacity(0.55);
    final center = Offset(_previewPoints[i].dx * size.width, _previewPoints[i].dy * size.height);
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: SeenlyPalette.paper, width: 2.5),
        ),
      ),
    );
  }
}

/// Draws a thick, gently curving road through [points] (fractions of the
/// paint size), with a dashed pale centerline on top — the same visual
/// language whether it's the small teaser preview or the full route.
class _RoadPainter extends CustomPainter {
  final List<Offset> points;
  final double roadWidth;
  final Color roadColor;
  Color get lineColor => _lineColor ?? SeenlyPalette.paper;
  final Color? _lineColor;

  _RoadPainter({
    required this.points,
    this.roadWidth = 15,
    this.roadColor = const Color(0xFFDCCFB2),
    Color? lineColor,
  }) : _lineColor = lineColor;

  Path _buildPath(Size size) {
    final abs = points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    final path = Path()..moveTo(abs.first.dx, abs.first.dy);
    if (abs.length == 2) {
      path.lineTo(abs[1].dx, abs[1].dy);
      return path;
    }
    // Thread a smooth curve through every point: each segment curves from
    // the current point toward the midpoint of the next pair, using the
    // point itself as the control — the standard "smooth polyline" trick,
    // finishing with a short straight run into the final stop.
    for (int i = 0; i < abs.length - 1; i++) {
      final current = abs[i];
      final next = abs[i + 1];
      final midX = (current.dx + next.dx) / 2;
      final midY = (current.dy + next.dy) / 2;
      path.quadraticBezierTo(current.dx, current.dy, midX, midY);
    }
    path.lineTo(abs.last.dx, abs.last.dy);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = _buildPath(size);

    final roadPaint = Paint()
      ..color = roadColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = roadWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, roadPaint);

    final dashPaint = Paint()
      ..color = lineColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      const dashLength = 9.0;
      const gapLength = 8.0;
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), dashPaint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.roadColor != roadColor;
}

/// The full route: every logged evening laid out as a little printed
/// stop card — a departure code, a destination, a duration, the poster
/// riding along — stacked one under the next like a slim log of tickets
/// rather than pins along a winding road. Tapping one opens the same
/// soft watched-preview card as before.
class EveningRoadScreen extends StatelessWidget {
  final List<DiaryEntry> entries;
  const EveningRoadScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
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
                      Text('the route'.tr, style: SeenlyText.serif(size: 20, weight: FontWeight.w600)),
                      Text(
                        nCount('nStops', entries.length),
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('no evenings on the road yet'.tr,
                          style: SeenlyText.emptyState()),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 60),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _StopTicketCard(
                        entry: entries[i],
                        index: i,
                        onTap: () => _openStop(context, entries[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openStop(BuildContext context, DiaryEntry entry) {
    showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
  }
}

const List<String> _stopMonths = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _stopDateLabel(DateTime d) => '${d.day} ${_stopMonths[d.month - 1]}';

IconData _stopMediaIcon(String mediaType) {
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

/// One evening, printed like a little station ticket instead of a pin
/// on a road: a date and a "boarded"/"reboarded" stamp up top, the
/// two stops of tonight's route in big station-board type with the
/// poster riding along the left edge, a dashed rail underneath with a
/// small train easing across it, and a footer line with the trip
/// length and however many hearts the evening earned. Cards stack
/// straight down the page — softly, like torn stubs collected in a
/// pocket — rather than winding side to side.
class _StopTicketCard extends StatelessWidget {
  final DiaryEntry entry;
  final int index;
  final VoidCallback onTap;
  const _StopTicketCard({required this.entry, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final route = routeForRuntime(runtimeMinutes: null, mediaType: entry.mediaType, seed: entry.id);
    final categoryColor = SeenlyPalette.mediaColor(entry.mediaType);
    final statusColor = entry.isRewatch ? SeenlyPalette.mustard : SeenlyPalette.sage;
    final statusLabel = entry.isRewatch ? 'REBOARDED' : 'ARRIVED';
    // A hair of tilt, alternating by index, so the stub doesn't look
    // machine-stamped — same trick the diary's scrapbook entries use.
    final angle = (index.isEven ? -1 : 1) * 0.012;

    return ScrollRevealEntrance(
      index: index,
      child: Transform.rotate(
        angle: angle,
        child: Transform.translate(
          // A slight overlap instead of a clean gap — each card rides just
          // over the bottom edge of the one above it, like a small stack of
          // tickets rather than a plain spaced-out list. This is a paint
          // -only shift (Flutter's Padding/margin reject negative values),
          // and since it grows with index, every consecutive pair still
          // overlaps by the same ~12px; later cards paint after earlier
          // ones, so the overlap naturally sits on top.
          offset: Offset(0, -12.0 * index),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(20),
                boxShadow: SeenlyPalette.softShadow,
                border: Border.all(color: SeenlyPalette.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date on the left, a soft status stamp on the right —
                  // the same beat as a real ticket's issue stamp.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 10.5, color: SeenlyPalette.inkFaint),
                          const SizedBox(width: 5),
                          Text(_stopDateLabel(entry.watchedAt),
                              style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint, weight: FontWeight.w600)),
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
                  // Poster stub + the route itself, station-code style.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 80,
                          child: entry.posterUrl != null && entry.posterUrl!.isNotEmpty
                              ? Image.network(
                                  entry.posterUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _posterFallback(entry, categoryColor),
                                )
                              : _posterFallback(entry, categoryColor),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _stationBlock(route.originCode, route.originCity, alignEnd: false),
                            ),
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _RailLine(color: categoryColor.withOpacity(0.55)),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: _stationBlock(route.destCode, route.destCity, alignEnd: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  _DashedDivider(color: SeenlyPalette.dashedBorder),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(size: 13, italic: true, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_durationLabel(route.minutes),
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                      if (entry.rating != null && entry.rating! > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.favorite, size: 10.5, color: SeenlyPalette.ratingColor(entry.rating)),
                        const SizedBox(width: 3),
                        Text('${entry.rating}/10',
                            style: SeenlyText.mono(
                                size: 9.5, color: SeenlyPalette.ratingColor(entry.rating), weight: FontWeight.w600)),
                      ],
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

  Widget _stationBlock(String code, String city, {required bool alignEnd}) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(code, style: SeenlyText.serif(size: 19, weight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(
            city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint),
          ),
        ],
      );

  Widget _posterFallback(DiaryEntry entry, Color color) => Container(
        color: color,
        alignment: Alignment.center,
        child: Icon(_stopMediaIcon(entry.mediaType), size: 20, color: SeenlyPalette.paper),
      );

  static String _durationLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

/// The dashed rail between two station codes, with a small train
/// riding its midpoint — this theme's answer to the dotted flight path
/// printed on a real ticket.
class _RailLine extends StatelessWidget {
  final Color color;
  const _RailLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: CustomPaint(
        painter: _RailPainter(color: color),
        child: Align(
          alignment: Alignment.center,
          child: Icon(Icons.train_outlined, size: 13, color: color),
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  final Color color;
  const _RailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3;
    const dash = 3.5, gap = 3.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) => oldDelegate.color != color;
}

/// A soft dashed rule used as the ticket's tear-line between the route
/// and the footer — evenly spaced regardless of the card's width.
class _DashedDivider extends StatelessWidget {
  final Color color;
  const _DashedDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              count,
              (_) => Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Container(width: dashWidth, height: 1, color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}

