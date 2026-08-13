import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/coach_routes.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A little coach-station stub for one logged evening — the "Evening
/// Route" theme's counterpart to `TicketWidget`. The runtime becomes a
/// real route (see `coach_routes.dart`): the movie is "now boarding" as
/// the destination, the runtime is the trip length, and the two
/// nearest-matching cities stand in for where you're "headed."
///
/// `tearProgress` (0..1) animates from "whole pass" to "torn at the
/// gate" — same body-and-stub split as a cinema ticket, since a coach
/// boarding pass really does tear the same way; what's different is
/// everything printed on it.
class BoardingPassWidget extends StatelessWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final int? runtimeMinutes;
  final CoachRoute? routeOverride;
  final double width;
  final double height;
  final double tearProgress;
  final bool compact;

  const BoardingPassWidget({
    super.key,
    required this.title,
    required this.mediaType,
    required this.watchedAt,
    this.rating,
    this.runtimeMinutes,
    this.routeOverride,
    this.width = 230,
    this.height = 100,
    this.tearProgress = 0,
    this.compact = false,
  });

  static const double _stubWidth = 50;
  static const double _notchR = 6;

  Color get _accent => SeenlyPalette.ratingColor(rating);
  Color get _categoryColor => SeenlyPalette.mediaColor(mediaType);
  CoachRoute get _route =>
      routeOverride ??
      routeForRuntime(
        runtimeMinutes: runtimeMinutes,
        mediaType: mediaType,
        seed: '$title-$watchedAt',
      );

  @override
  Widget build(BuildContext context) {
    final mainWidth = width - _stubWidth - 2;
    final mainOffset = Offset(-tearProgress * 10, tearProgress * 4);
    final stubOffset = Offset(tearProgress * 26, tearProgress * 34);
    final mainAngle = -tearProgress * 0.10;
    final stubAngle = tearProgress * 0.42;
    final route = _route;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.translate(
              offset: mainOffset,
              child: Transform.rotate(
                angle: mainAngle,
                child: _PassBody(
                  width: mainWidth,
                  height: height,
                  accent: _accent,
                  categoryColor: _categoryColor,
                  title: title,
                  mediaType: mediaType,
                  rating: rating,
                  watchedAt: watchedAt,
                  route: route,
                  compact: compact,
                ),
              ),
            ),
          ),
          Positioned(
            left: mainWidth + 2,
            top: 0,
            child: Transform.translate(
              offset: stubOffset,
              child: Transform.rotate(
                angle: stubAngle,
                child: _PassStub(
                  width: _stubWidth,
                  height: height,
                  accent: _accent,
                  categoryColor: _categoryColor,
                  seed: '$title-$watchedAt',
                  route: route,
                  compact: compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassBody extends StatelessWidget {
  final double width;
  final double height;
  final Color accent;
  final Color categoryColor;
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final CoachRoute route;
  final bool compact;

  const _PassBody({
    required this.width,
    required this.height,
    required this.accent,
    required this.categoryColor,
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.watchedAt,
    required this.route,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.16), blurRadius: 20, offset: const Offset(0, 9)),
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipPath(
        clipper: _MainBodyClipper(notchRadius: BoardingPassWidget._notchR),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeenlyPalette.paper, Color.lerp(SeenlyPalette.paper, categoryColor, 0.05)!],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: compact ? 4 : 5, width: double.infinity, color: categoryColor),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 6 : 12, compact ? 5 : 9, 8, compact ? 5 : 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // The route line — two station codes and a dashed
                      // path between them, the same beat as a real
                      // boarding pass's route strip.
                      Row(
                        children: [
                          Text(route.originCode,
                              style: SeenlyText.mono(size: compact ? 7.5 : 9.5, color: SeenlyPalette.ink, weight: FontWeight.w700)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: CustomPaint(
                                size: Size.fromHeight(compact ? 8 : 10),
                                painter: _RoutePainter(color: SeenlyPalette.inkFaint.withOpacity(0.55)),
                              ),
                            ),
                          ),
                          Text(route.destCode,
                              style: SeenlyText.mono(size: compact ? 7.5 : 9.5, color: SeenlyPalette.ink, weight: FontWeight.w700)),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text('NOW BOARDING',
                            style: SeenlyText.mono(size: 6.5, color: categoryColor, weight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(italic: true, size: 13),
                        ),
                      ],
                      Row(
                        children: [
                          Text(_durationLabel(route.minutes),
                              style: SeenlyText.mono(size: compact ? 6.5 : 8.5, color: SeenlyPalette.inkFaint)),
                          if (!compact) ...[
                            const SizedBox(width: 8),
                            Text('· ${_shortDate(watchedAt)}',
                                style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint)),
                          ],
                          const Spacer(),
                          if (rating != null && rating! > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.favorite, size: compact ? 7 : 10, color: accent),
                                const SizedBox(width: 3),
                                Text('$rating/10',
                                    style: SeenlyText.mono(size: compact ? 6.5 : 9, color: accent, weight: FontWeight.w600)),
                              ],
                            ),
                        ],
                      ),
                    ],
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

class _PassStub extends StatelessWidget {
  final double width;
  final double height;
  final Color accent;
  final Color categoryColor;
  final Object seed;
  final CoachRoute route;
  final bool compact;

  const _PassStub({
    required this.width,
    required this.height,
    required this.accent,
    required this.categoryColor,
    required this.seed,
    required this.route,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(accent, categoryColor, 0.35)!;
    final row = 8 + boardingJitter(seed, 0, 18, salt: 5).round();
    const seatLetters = ['A', 'B', 'C', 'D', 'F'];
    final seatLetter = seatLetters[boardingJitter(seed, 0, 4.99, salt: 6).floor()];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: SeenlyPalette.ink.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 7))],
      ),
      child: ClipPath(
        clipper: _StubClipper(notchRadius: BoardingPassWidget._notchR),
        child: Container(
          width: width,
          height: height,
          color: tint.withOpacity(0.16),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              'SEAT $row$seatLetter · ${route.destCode}',
              style: SeenlyText.mono(size: compact ? 6 : 7.5, color: tint, weight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _monthAbbrev = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
];

/// A short, printed-boarding-pass-style date — "JUL 21" — kept as a
/// tiny local helper rather than pulling in `intl` just for this.
String _shortDate(DateTime d) => '${_monthAbbrev[d.month - 1]} ${d.day}';

String _durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m route';
  if (m == 0) return '${h}h route';
  return '${h}h ${m}m route';
}

/// A short dashed line with a small bus riding along it, standing in
/// for the dotted flight path printed between the two cities on a real
/// boarding pass.
class _RoutePainter extends CustomPainter {
  final Color color;
  const _RoutePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 3.0, gap = 2.5;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
      x += dash + gap;
    }
    // a tiny bus body riding the midpoint of the line
    final busPaint = Paint()..color = color;
    final cx = size.width / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, y), width: 8, height: 4), const Radius.circular(1)),
      busPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.color != color;
}

/// Rounded rect with a bite out of the top-right and bottom-right — the
/// half of the perforation that stays with the main body once it tears
/// away from the stub. Same geometry as the ticket theme's clipper.
class _MainBodyClipper extends CustomClipper<Path> {
  final double notchRadius;
  const _MainBodyClipper({required this.notchRadius});

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: const Radius.circular(10),
        bottomLeft: const Radius.circular(10),
        topRight: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      ));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(size.width, 0), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height), radius: notchRadius));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant _MainBodyClipper oldDelegate) => oldDelegate.notchRadius != notchRadius;
}

class _StubClipper extends CustomClipper<Path> {
  final double notchRadius;
  const _StubClipper({required this.notchRadius});

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Offset.zero & size,
        topRight: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
        topLeft: const Radius.circular(3),
        bottomLeft: const Radius.circular(3),
      ));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, 0), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(0, size.height), radius: notchRadius));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant _StubClipper oldDelegate) => oldDelegate.notchRadius != notchRadius;
}

/// A tiny decorative boarding pass, used inside the route board's
/// illustration instead of a plain colored rectangle — same notch
/// language as `MiniTicketChip`, kept local so this file has no
/// dependency on the ticket theme.
class MiniBoardingChip extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final double rotation;

  const MiniBoardingChip({
    super.key,
    required this.color,
    this.width = 16,
    this.height = 24,
    this.rotation = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: ClipPath(
        clipper: _MiniChipClipper(),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.white.withOpacity(0.4), width: 0.6),
          ),
        ),
      ),
    );
  }
}

class _MiniChipClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final r = (size.height * 0.16).clamp(1.5, 4.0).toDouble();
    final base = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.22)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: r));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}

/// Deterministic pseudo-random value in `[min, max]` for a given seed —
/// mirrors `seededJitter` in `ticket.dart`, kept local so this file has
/// no dependency on the ticket theme.
double boardingJitter(Object seed, double min, double max, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt);
  return min + r.nextDouble() * (max - min);
}
