import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// One evening, built — the "Город из просмотренного" theme's stand-in
/// for a ticket/stamp/pass. The rating decides the *tier* (how grand a
/// building gets to be), never whether it looks good — even a quiet,
/// unrated evening is a real little cottage, not a punished eyesore.
/// Media type only tints the window-light and roof accent, the same
/// modest role [SeenlyPalette.mediaColor] plays everywhere else.
///
/// `rise` (0..1) lets one widget animate from "bare plot" to "standing
/// finished" — height scales with it and windows light up in sequence
/// as it climbs, so the same widget draws both the construction moment
/// and how a building just sits in the skyline afterward (rise = 1).
class BuildingTier {
  final double heightFactor; // relative to BuildingWidget.height
  final int windowRows;
  final int windowsPerRow;
  final _Roof roof;

  const BuildingTier({
    required this.heightFactor,
    required this.windowRows,
    required this.windowsPerRow,
    required this.roof,
  });
}

enum _Roof { flat, peaked, spire }

/// unrated/0 → a quiet cottage · 1-3 → a modest flat · 4-6 → a
/// townhouse · 7-8 → a lit-up high-rise · 9-10 → a landmark tower.
/// Every tier is a whole, cared-for little building — the difference is
/// scale, never quality.
BuildingTier tierForRating(int? rating) {
  final r = rating ?? 0;
  if (r >= 9) return const BuildingTier(heightFactor: 1.0, windowRows: 5, windowsPerRow: 3, roof: _Roof.spire);
  if (r >= 7) return const BuildingTier(heightFactor: 0.8, windowRows: 4, windowsPerRow: 3, roof: _Roof.flat);
  if (r >= 4) return const BuildingTier(heightFactor: 0.58, windowRows: 3, windowsPerRow: 2, roof: _Roof.peaked);
  if (r >= 1) return const BuildingTier(heightFactor: 0.4, windowRows: 2, windowsPerRow: 2, roof: _Roof.peaked);
  return const BuildingTier(heightFactor: 0.28, windowRows: 1, windowsPerRow: 1, roof: _Roof.peaked);
}

class BuildingWidget extends StatelessWidget {
  final String title;
  final String mediaType;
  final int? rating;
  final DateTime watchedAt;
  final double width;
  final double height;
  final double rise; // 0..1
  final bool compact;
  final bool showLabel;
  final Color labelColor;

  const BuildingWidget({
    super.key,
    required this.title,
    required this.mediaType,
    required this.watchedAt,
    this.rating,
    this.width = 54,
    this.height = 130,
    this.rise = 1.0,
    this.compact = false,
    this.showLabel = false,
    this.labelColor = SeenlyPalette.paper,
  });

  Color get _accent => SeenlyPalette.ratingColor(rating);
  Color get _categoryColor => SeenlyPalette.mediaColor(mediaType);

  @override
  Widget build(BuildContext context) {
    final tier = tierForRating(rating);
    final r = rise.clamp(0.0, 1.0);
    final builtHeight = height * tier.heightFactor * r;
    // Warmer and lighter than the ink backdrop it always sits against,
    // so the silhouette actually reads as a building rather than
    // dissolving into the night sky behind it.
    final bodyColor = Color.lerp(SeenlyPalette.ink, _accent, 0.45)!;
    final totalWindows = tier.windowRows * tier.windowsPerRow;

    final visual = SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          height: builtHeight.clamp(0.0, height),
          child: r <= 0.02
              ? null
              : Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    if (tier.roof == _Roof.spire && r > 0.9)
                      Positioned(
                        top: -14,
                        child: Container(width: 1.6, height: 14, color: _categoryColor.withOpacity(0.8)),
                      ),
                    if (tier.roof == _Roof.peaked)
                      Positioned(
                        top: -8,
                        child: CustomPaint(
                          size: Size(width + 4, 9),
                          painter: _RoofPainter(color: bodyColor),
                        ),
                      ),
                    Positioned.fill(
                      top: tier.roof == _Roof.peaked ? 4 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: bodyColor,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(tier.roof == _Roof.flat ? 3 : 1)),
                          boxShadow: [
                            BoxShadow(color: SeenlyPalette.ink.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 3)),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(tier.windowRows, (row) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(tier.windowsPerRow, (col) {
                                final index = row * tier.windowsPerRow + col;
                                final litAt = (index + 1) / totalWindows;
                                final lit = r >= litAt * 0.92;
                                return Container(
                                  width: compact ? 3 : 5,
                                  height: compact ? 3 : 5,
                                  decoration: BoxDecoration(
                                    color: lit ? _categoryColor.withOpacity(0.9) : Colors.black.withOpacity(0.3),
                                    boxShadow: lit
                                        ? [BoxShadow(color: _categoryColor.withOpacity(0.6), blurRadius: 3)]
                                        : null,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                );
                              }),
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    if (!showLabel) return visual;

    // A real row in the layout, not an overflowing Positioned — so the
    // title is guaranteed on-screen rather than clipped by whatever
    // container the building sits in.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        visual,
        const SizedBox(height: 5),
        SizedBox(
          width: width + 26,
          child: AnimatedOpacity(
            opacity: r >= 0.95 ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              title,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(size: 8.5, color: labelColor, weight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoofPainter extends CustomPainter {
  final Color color;
  const _RoofPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RoofPainter oldDelegate) => oldDelegate.color != color;
}
