import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A little ink stamp for one logged evening — the passport theme's
/// counterpart to `TicketWidget`. Two concentric hand-jittered circles
/// stand in for a ring, deliberately imperfect (a real stamp never
/// lands as a clean geometric circle), colored the same way a ticket
/// already is: ink = how the evening felt ([SeenlyPalette.ratingColor]),
/// the thin category tag = what it plainly was
/// ([SeenlyPalette.mediaColor]).
///
/// [press] (0..1) lets one widget animate all the way from "barely
/// touched the page yet" to "fully inked" — 0 is a faint ghost outline
/// (used mid-descent by the stamp-drop overlay), 1 is how it sits at
/// rest everywhere else, including in the passport book.
class StampWidget extends StatelessWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final double size;
  final double press;
  final bool compact;

  const StampWidget({
    super.key,
    required this.title,
    required this.mediaType,
    required this.watchedAt,
    this.rating,
    this.size = 128,
    this.press = 1.0,
    this.compact = false,
  });

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC', //
  ];

  Color get _ink => SeenlyPalette.ratingColor(rating);
  Color get _categoryColor => SeenlyPalette.mediaColor(mediaType);
  String get _seed => '$title-$watchedAt-$mediaType';

  @override
  Widget build(BuildContext context) {
    final inkOpacity = 0.16 + 0.84 * press.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: inkOpacity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipPath(
              clipper: _RoughCircleClipper(seed: _seed),
              child: Container(color: _ink),
            ),
            Padding(
              padding: EdgeInsets.all(size * 0.05),
              child: ClipPath(
                clipper: _RoughCircleClipper(seed: _seed),
                child: Container(color: Color.lerp(SeenlyPalette.paper, _ink, 0.07)),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(size * (compact ? 0.24 : 0.17)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 4 : 6, vertical: compact ? 1 : 1.5),
                    decoration: BoxDecoration(
                      border: Border.all(color: _categoryColor.withOpacity(0.85), width: 1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(mediaType,
                        style: SeenlyText.mono(
                            size: compact ? 6 : 8,
                            color: _categoryColor,
                            weight: FontWeight.w600)),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(italic: true, size: 10.5, color: _ink),
                    ),
                    const SizedBox(height: 4),
                  ] else
                    const SizedBox(height: 2),
                  Text('${_months[watchedAt.month - 1]} ${watchedAt.day}',
                      style: SeenlyText.mono(
                          size: compact ? 5.5 : 7.5, color: _ink, weight: FontWeight.w600)),
                  if (!compact && (rating ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('$rating/10',
                          style: SeenlyText.mono(size: 7.5, color: _ink, weight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rough, hand-jittered circle — sampling points around a ring and
/// nudging each one's radius by a few percent, seeded so the same
/// evening always gets the same imperfect shape. The same
/// "difference of paths" trick as elsewhere in the app; here it's the
/// jitter itself that does the character work rather than a clip.
class _RoughCircleClipper extends CustomClipper<Path> {
  final String seed;
  final int points;

  const _RoughCircleClipper({required this.seed, this.points = 26});

  @override
  Path getClip(Size size) {
    final r = math.Random(seed.hashCode);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(size.width, size.height) / 2;
    final path = Path();
    for (int i = 0; i < points; i++) {
      final angle = (i / points) * 2 * math.pi;
      final jitter = 1.0 + (r.nextDouble() - 0.5) * 0.07;
      final rad = baseR * jitter;
      final x = cx + math.cos(angle) * rad;
      final y = cy + math.sin(angle) * rad;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _RoughCircleClipper oldDelegate) => oldDelegate.seed != seed;
}

/// Deterministic pseudo-random value in `[min, max]` for a given seed —
/// mirrors `seededJitter` in `ticket.dart`, kept local here so this
/// file has no dependency on the ticket theme.
double stampJitter(Object seed, double min, double max, {int salt = 0}) {
  final r = math.Random(seed.hashCode ^ salt);
  return min + r.nextDouble() * (max - min);
}
