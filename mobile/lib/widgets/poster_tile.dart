import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'shrink_to_fit_text.dart';

/// A 2:3 poster block. If [posterUrl] is null or fails to load, falls back
/// to a flat color fill (from [fallbackColor], or rotated from the palette)
/// with the title overlaid — the same "illustrated poster" placeholder used
/// throughout the mockups instead of a broken-image icon.
class PosterTile extends StatelessWidget {
  final String? posterUrl;
  final String title;
  final Color? fallbackColor;
  final VoidCallback? onTap;
  final Widget? badge; // e.g. a small check/bookmark in the corner
  final bool showLabel; // set false when the title is already shown nearby

  const PosterTile({
    super.key,
    required this.title,
    this.posterUrl,
    this.fallbackColor,
    this.onTap,
    this.badge,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = fallbackColor ?? SeenlyPalette.accent;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: posterUrl != null && posterUrl!.isNotEmpty
                  ? Image.network(
                      posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(color),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _fallback(color);
                      },
                    )
                  : _fallback(color, showTitle: showLabel),
            ),
            if (showLabel && posterUrl != null && posterUrl!.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  color: Colors.black.withOpacity(0.35),
                  child: ShrinkToFitText(
                    title,
                    maxLines: 1,
                    minFontSize: 7.5,
                    style: SeenlyText.serif(
                        size: 10, color: SeenlyPalette.paper, italic: false, enforceFloor: false),
                  ),
                ),
              ),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
  }

  Widget _fallback(Color color, {bool showTitle = false}) {
    return Container(
      color: color,
      alignment: Alignment.bottomLeft,
      padding: showTitle ? const EdgeInsets.all(5) : EdgeInsets.zero,
      child: showTitle
          ? Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black.withOpacity(0.2),
              width: double.infinity,
              child: ShrinkToFitText(
                title,
                maxLines: 1,
                minFontSize: 7.5,
                style: SeenlyText.serif(size: 10, color: SeenlyPalette.paper, enforceFloor: false),
              ),
            )
          : null,
    );
  }
}
