import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A little cinema-stub card for one logged evening — main body + a
/// perforated stub, same shape language as a real ticket, dressed in the
/// app's own paper-and-plum palette instead of glossy box-office red.
///
/// `tearProgress` (0..1) lets one widget animate from "whole ticket" to
/// "torn in half" — 0 is how it sits at rest (in the jar, in the scatter
/// view), 1 is mid-tear (used by [TicketDropOverlay]). The stub always
/// carries the date; the body always carries the title, media type, and
/// rating, so either half still reads as "this evening" if a gust of
/// physics separates them further than expected.
class TicketWidget extends StatelessWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final double width;
  final double height;
  final double tearProgress;
  final bool compact; // smaller text/padding for the jar's tiny chips

  const TicketWidget({
    super.key,
    required this.title,
    required this.mediaType,
    required this.watchedAt,
    this.rating,
    this.width = 220,
    this.height = 96,
    this.tearProgress = 0,
    this.compact = false,
  });

  static const double _stubWidth = 46;
  static const double _notchR = 6;

  // The ticket's color is how the evening *felt* (the 1-10 rating), not
  // what it was — a 9/10 comedy and a 9/10 documentary land the same
  // warm color; an unrated evening stays a quiet neutral rather than
  // borrowing either end of the scale. This still drives the rating
  // text/heart and the stub's tint.
  Color get _accent => SeenlyPalette.ratingColor(rating);

  // The category tag, though, isn't about feeling — it's a plain fact
  // (movie/series/game/...) that's true the second the ticket exists,
  // rating or not. Giving it the real media color instead of borrowing
  // the neutral rating-gray is what keeps a fresh, unrated ticket from
  // reading as flat and colorless.
  Color get _categoryColor => SeenlyPalette.mediaColor(mediaType);

  @override
  Widget build(BuildContext context) {
    final mainWidth = width - _stubWidth - 2;
    // A ticket doesn't fall apart symmetrically — the stub (lighter, no
    // poster weight behind it) drifts further and spins a touch more than
    // the body it tore away from.
    final mainOffset = Offset(-tearProgress * 10, tearProgress * 4);
    final stubOffset = Offset(tearProgress * 26, tearProgress * 34);
    final mainAngle = -tearProgress * 0.10;
    final stubAngle = tearProgress * 0.42;

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
                child: _TicketBody(
                  width: mainWidth,
                  height: height,
                  accent: _accent,
                  categoryColor: _categoryColor,
                  title: title,
                  mediaType: mediaType,
                  rating: rating,
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
                child: _TicketStub(
                  width: _stubWidth,
                  height: height,
                  accent: _accent,
                  categoryColor: _categoryColor,
                  watchedAt: watchedAt,
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

class _TicketBody extends StatelessWidget {
  final double width;
  final double height;
  final Color accent;
  final Color categoryColor;
  final String title;
  final String mediaType;
  final int? rating;
  final bool compact;

  const _TicketBody({
    required this.width,
    required this.height,
    required this.accent,
    required this.categoryColor,
    required this.title,
    required this.mediaType,
    required this.rating,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    // A soft, warm-toned lift so the ticket reads as an object resting on
    // the page rather than a flat sticker printed onto it. Drawn on this
    // outer box rather than the clipped paper itself, so the blur isn't
    // cut off by the notches.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.16),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipPath(
        clipper: _MainBodyClipper(notchRadius: TicketWidget._notchR),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.paper,
                Color.lerp(SeenlyPalette.paper, categoryColor, 0.05)!,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A little stripe of the title's own color along the top —
              // true from the moment the ticket exists, rating or not, so
              // there's always something bright here even before you've
              // said how the evening felt.
              Container(height: compact ? 4 : 5, width: double.infinity, color: categoryColor),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 6 : 13, compact ? 5 : 10, 8, compact ? 5 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 5 : 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: categoryColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          mediaType,
                          style: SeenlyText.mono(
                              size: compact ? 7 : 9, color: categoryColor),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 5),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(italic: true, size: 13),
                        ),
                      ],
                      if (rating != null && rating! > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite, size: compact ? 7 : 10, color: accent),
                            const SizedBox(width: 3),
                            Text('$rating/10',
                                style: SeenlyText.mono(
                                    size: compact ? 6.5 : 9,
                                    color: accent,
                                    weight: FontWeight.w600)),
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

class _TicketStub extends StatelessWidget {
  final double width;
  final double height;
  final Color accent;
  final Color categoryColor;
  final DateTime watchedAt;
  final bool compact;

  const _TicketStub({
    required this.width,
    required this.height,
    required this.accent,
    required this.categoryColor,
    required this.watchedAt,
    required this.compact,
  });

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    // Blends in a hint of the category color so the stub isn't left
    // behind in plain neutral gray on an otherwise unrated, but now
    // colorful, ticket.
    final tint = Color.lerp(accent, categoryColor, 0.35)!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: SeenlyPalette.ink.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipPath(
        clipper: _StubClipper(notchRadius: TicketWidget._notchR),
        child: Container(
          width: width,
          height: height,
          color: tint.withOpacity(0.16),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              '${_months[watchedAt.month - 1]} ${watchedAt.day}',
              style: SeenlyText.mono(
                  size: compact ? 6.5 : 8.5, color: tint, weight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded rect with a bite taken out of the top-right and bottom-right —
/// the half of the perforation that stays with the main body once it
/// tears away from the stub.
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
  bool shouldReclip(covariant _MainBodyClipper oldDelegate) =>
      oldDelegate.notchRadius != notchRadius;
}

/// The stub's half of the same perforation — a bite out of its top-left
/// and bottom-left, so the two pieces still read as torn from one ticket
/// even mid-fall.
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
  bool shouldReclip(covariant _StubClipper oldDelegate) =>
      oldDelegate.notchRadius != notchRadius;
}

/// A tiny decorative ticket, used inside the jar illustration instead of
/// a plain colored rectangle — small side notches so even at this scale
/// it reads as "a little torn ticket," not just a chip of color.
class MiniTicketChip extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final double rotation;

  const MiniTicketChip({
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
        clipper: _MiniTicketClipper(),
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

class _MiniTicketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final r = (size.height * 0.16).clamp(1.5, 4.0).toDouble();
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(size.width * 0.22)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, size.height / 2), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, size.height / 2), radius: r));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}

/// Deterministic "random" jitter for a chip/ticket — same entry always
/// lands in the same spot within a render, so the jar and scatter view
/// don't visibly reshuffle themselves on every rebuild.
double seededJitter(Object seed, double min, double max, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt);
  return min + r.nextDouble() * (max - min);
}
