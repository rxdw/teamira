import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart';
import '../theme/clay_kit.dart';

/// The signature "scrapbook" element: a small square photo, slightly
/// rotated, with a strip of washi tape at the top and a handwritten
/// caption underneath. [rotationTurns] is a fraction of a full turn
/// (e.g. -0.02 ~= -2deg) — pass alternating small values so a row of
/// these doesn't look mechanically repeated.
class PolaroidCard extends StatelessWidget {
  final String? posterUrl;
  final String caption;
  final Color fallbackColor;
  Color get tapeColor => _tapeColor ?? SeenlyPalette.tapeRose;
  final Color? _tapeColor;
  final double rotationTurns;
  final double size;
  final VoidCallback? onTap;

  PolaroidCard({
    super.key,
    required this.caption,
    this.posterUrl,
    required this.fallbackColor,
    Color? tapeColor,
    this.rotationTurns = -0.02,
    this.size = 70,
    this.onTap,
  }) : _tapeColor = tapeColor;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.94,
      child: Transform.rotate(
        angle: rotationTurns * 6.28319,
        child: Container(
          width: size + 12,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 9),
          decoration: ClayBoxDecoration(
            boxShadow: SeenlyPalette.flatCardShadow,
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -12,
                left: (size + 12) / 2 - 22,
                child: Transform.rotate(
                  angle: -0.07,
                  child: Container(
                    width: 32,
                    height: 12,
                    color: tapeColor.withOpacity(0.8),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: posterUrl != null && posterUrl!.isNotEmpty
                          ? FadeInNetworkImage(
                              url: posterUrl!,
                              fit: BoxFit.cover,
                              placeholder: Container(color: fallbackColor),
                            )
                          : Container(color: fallbackColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: size,
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 10, italic: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
