import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'shrink_to_fit_text.dart';
import 'wow_motion.dart';

/// Drop-in replacement for [PosterTile] that dresses every poster in the
/// app in whichever [LogTheme] is chosen in Settings — the same look that
/// already governs the logging ritual (`log_ritual.dart`). Same 2:3
/// footprint and constructor shape as PosterTile, so it slots into every
/// grid/row PosterTile used to sit in (Collections, a collection's full
/// grid, the Diary preview row, the Profile shelf, Wrapped's favorite,
/// "similar titles"): picking a theme once re-dresses all of them, plus
/// the logging ritual, at the same time — nothing left half-dressed.
///
/// - **ticket**: a little filmstrip — sprocket notches down both edges,
///   a corner stub with the media type.
/// - **coach**: a boarding-pass stub — a single tear notch, a dashed
///   line, a barcode strip.
/// - **garden**: a plant marker — a punched hanging-hole, a soft paper
///   label instead of a bar.
class ThemedPosterTile extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final Color? fallbackColor;
  final String? mediaType;
  final VoidCallback? onTap;
  final Widget? badge;
  // Callers that build a mosaic/masonry layout (varied tile heights) pass
  // something other than the standard 2:3 poster ratio. Defaults to the
  // normal poster shape so every other call site is unaffected.
  final double aspectRatio;
  // Vertical pixel offset applied to the poster art itself (not the whole
  // tile/frame/badge) — driven by scroll position from the caller (see
  // _ParallaxPoster in collection_full_screen.dart). Zero by default, so
  // every other call site renders exactly as before.
  final double parallax;

  const ThemedPosterTile({
    super.key,
    required this.title,
    this.posterUrl,
    this.fallbackColor,
    this.mediaType,
    this.onTap,
    this.badge,
    this.aspectRatio = 2 / 3,
    this.parallax = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LogThemeService>().theme;
    final color = fallbackColor ?? SeenlyPalette.accent;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.95,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: switch (theme) {
          LogTheme.ticket => _TicketPoster(
              title: title, posterUrl: posterUrl, color: color, mediaType: mediaType, badge: badge, parallax: parallax),
          LogTheme.coach => _CoachPoster(
              title: title, posterUrl: posterUrl, color: color, mediaType: mediaType, badge: badge, parallax: parallax),
          LogTheme.garden => _GardenPoster(
              title: title, posterUrl: posterUrl, color: color, mediaType: mediaType, badge: badge, parallax: parallax),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------

Widget _posterFill(String? url, Color color, String title, {String? mediaType, double parallax = 0}) {
  Widget content;
  if (url != null && url.isNotEmpty) {
    // YouTube/Twitch imports (media_type == "video") only ever have a
    // 16:9 video thumbnail on file, never a real vertical poster — see
    // backend/app/adapters/youtube.py::_to_media_item. BoxFit.cover on
    // that inside our 2:3 frame chops the sides off and zooms in on
    // whatever's dead center, which is why those tiles look like a
    // random crop instead of a cover. Letterbox them instead.
    if (mediaType == 'video') {
      content = _letterboxedFill(url, color, title);
    } else {
      content = FadeInNetworkImage(
        url: url,
        fit: BoxFit.cover,
        placeholder: _fallbackFill(color, title),
      );
    }
  } else {
    content = _fallbackFill(color, title, showTitle: true);
  }
  if (parallax == 0) return content;
  // Scaled up first so the vertical shift below never uncovers empty
  // space at the top/bottom edge of the frame — the outer ClipPath in
  // each theme's poster (sprocket/tag/edge-notch shape) then trims the
  // overscan back down to the tile's real footprint.
  return Transform.translate(
    offset: Offset(0, parallax),
    child: Transform.scale(scale: 1.18, child: content),
  );
}

/// A landscape thumbnail placed inside the app's vertical 2:3 poster
/// frame: a blurred, cropped copy of the same thumbnail fills the frame
/// edge-to-edge as a backdrop, and the *whole, uncropped* thumbnail sits
/// centered on top of it. Nothing about the actual frame is lost — it's
/// padded top/bottom instead of chopped left/right.
Widget _letterboxedFill(String url, Color color, String title) {
  return Stack(
    fit: StackFit.expand,
    children: [
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
        child: FadeInNetworkImage(
          url: url,
          fit: BoxFit.cover,
          placeholder: Container(color: color),
        ),
      ),
      Container(color: Colors.black.withOpacity(0.18)),
      Center(
        child: FadeInNetworkImage(
          url: url,
          fit: BoxFit.contain,
          placeholder: _fallbackFill(color, title),
        ),
      ),
    ],
  );
}

Widget _fallbackFill(Color color, String title, {bool showTitle = false}) {
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

IconData _iconForMediaType(String? mediaType, IconData fallback) {
  switch (mediaType) {
    case 'movie':
      return Icons.local_movies_outlined;
    case 'series':
      return Icons.live_tv_outlined;
    case 'anime':
      return Icons.auto_awesome_outlined;
    case 'game':
      return Icons.sports_esports_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'manga':
      return Icons.import_contacts_outlined;
    case 'video':
      return Icons.smart_display_outlined;
    default:
      return fallback;
  }
}

/// A dashed horizontal line — used as the "tear here" mark for the ticket
/// and coach themes. Same dash rhythm as `DashedBox` elsewhere in the app.
class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(color: color),
      size: const Size(double.infinity, 1.4),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    const dashWidth = 4.0;
    const gapWidth = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + dashWidth).clamp(0, size.width), 0), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

/// A row of short vertical bars — a little barcode, for the coach theme's
/// boarding-pass stub.
class _BarcodePainter extends CustomPainter {
  final Color color;
  const _BarcodePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rnd = [2.0, 1.0, 3.0, 1.0, 1.5, 2.5, 1.0, 2.0, 1.5, 3.0, 1.0, 2.0];
    double x = 0;
    var i = 0;
    while (x < size.width) {
      final w = rnd[i % rnd.length];
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w + 2;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------
// Ticket (cinema)
// ---------------------------------------------------------------------

class _TicketPoster extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final Color color;
  final String? mediaType;
  final Widget? badge;
  final double parallax;

  const _TicketPoster({
    required this.title,
    required this.posterUrl,
    required this.color,
    this.mediaType,
    this.badge,
    this.parallax = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _SprocketClipper(sprockets: 6, notchRadius: 3.4, cornerRadius: 9),
      child: Container(
        color: SeenlyPalette.paper,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _posterFill(posterUrl, color, title, mediaType: mediaType, parallax: parallax),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
  }
}

/// Rounded rect with evenly-spaced semicircle notches cut out of both
/// side edges — the little "sprocket holes" of a filmstrip/ticket.
class _SprocketClipper extends CustomClipper<Path> {
  final int sprockets;
  final double notchRadius;
  final double cornerRadius;
  const _SprocketClipper({required this.sprockets, this.notchRadius = 4, this.cornerRadius = 8});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    final notches = Path();
    for (var i = 0; i < sprockets; i++) {
      final fy = (i + 0.5) / sprockets * size.height;
      if (fy < cornerRadius * 1.4 || fy > size.height - cornerRadius * 1.4) continue;
      notches.addOval(Rect.fromCircle(center: Offset(0, fy), radius: notchRadius));
      notches.addOval(Rect.fromCircle(center: Offset(size.width, fy), radius: notchRadius));
    }
    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant _SprocketClipper oldClipper) =>
      oldClipper.sprockets != sprockets || oldClipper.notchRadius != notchRadius;
}

// ---------------------------------------------------------------------
// Coach (bus / boarding pass)
// ---------------------------------------------------------------------

class _CoachPoster extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final Color color;
  final String? mediaType;
  final Widget? badge;
  final double parallax;

  const _CoachPoster({
    required this.title,
    required this.posterUrl,
    required this.color,
    this.mediaType,
    this.badge,
    this.parallax = 0,
  });

  static const double _stubH = 14;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _EdgeNotchClipper(bottomInset: _stubH, notchRadius: 5, cornerRadius: 9),
      child: Container(
        color: SeenlyPalette.paper,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: _stubH),
              child: _posterFill(posterUrl, color, title, mediaType: mediaType, parallax: parallax),
            ),
            Positioned(
              left: 4,
              right: 4,
              bottom: _stubH,
              child: _DashedLine(color: SeenlyPalette.dashedBorder),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _stubH,
              child: Container(
                color: SeenlyPalette.cork,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: CustomPaint(painter: _BarcodePainter(color: SeenlyPalette.ink.withOpacity(0.55))),
              ),
            ),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
  }
}

/// Rounded rect with a single pair of semicircle notches cut into the
/// left/right edges, [bottomInset] logical pixels up from the bottom
/// edge — the tear point on a boarding-pass stub. Measured as an
/// absolute inset (not a fraction of height) so it lines up exactly
/// with the stub bar and dashed line above it, whatever size this tile
/// is actually laid out at.
class _EdgeNotchClipper extends CustomClipper<Path> {
  final double bottomInset;
  final double notchRadius;
  final double cornerRadius;
  const _EdgeNotchClipper(
      {required this.bottomInset, this.notchRadius = 5, this.cornerRadius = 8});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    if (bottomInset <= 0) return path;
    final fy = size.height - bottomInset;
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, fy), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(size.width, fy), radius: notchRadius));
    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant _EdgeNotchClipper oldClipper) =>
      oldClipper.bottomInset != bottomInset;
}

// ---------------------------------------------------------------------
// Garden (plant marker)
// ---------------------------------------------------------------------

class _GardenPoster extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final Color color;
  final String? mediaType;
  final Widget? badge;
  final double parallax;

  const _GardenPoster({
    required this.title,
    required this.posterUrl,
    required this.color,
    this.mediaType,
    this.badge,
    this.parallax = 0,
  });

  static const double _labelH = 22;

  @override
  Widget build(BuildContext context) {
    // The cover art already carries the title, so the name plate below is
    // redundant whenever a real poster image is loading/loaded. It's only
    // useful as a fallback when there's no cover to read the title off of.
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    return ClipPath(
      clipper: const _TagHoleClipper(cornerRadius: 12, holeRadius: 5),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.35), width: 1.5)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 12, bottom: hasPoster ? 0 : _labelH),
              child: _posterFill(posterUrl, color, title, mediaType: mediaType, parallax: parallax),
            ),
            // Soft paper label, like a plant marker's name strip, rather
            // than a hard bar — no straight-across color block. Fallback
            // only (see hasPoster above).
            if (!hasPoster)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _labelH,
                child: Container(
                  color: SeenlyPalette.paper,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(_iconForMediaType(mediaType, Icons.local_florist_outlined), size: 11, color: color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ShrinkToFitText(
                          title,
                          maxLines: 1,
                          minFontSize: 8,
                          style: SeenlyText.serif(
                              size: 10.5, italic: true, color: SeenlyPalette.ink, enforceFloor: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (badge != null) Positioned(top: hasPoster ? 4 : 14, right: 4, child: badge!),
          ],
        ),
      ),
    );
  }
}

/// Rounded rect with one small hole punched near the top-center — the
/// hanging-string hole of a garden plant marker/tag.
class _TagHoleClipper extends CustomClipper<Path> {
  final double cornerRadius;
  final double holeRadius;
  const _TagHoleClipper({this.cornerRadius = 10, this.holeRadius = 5});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    final hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(size.width / 2, holeRadius + 4), radius: holeRadius));
    return Path.combine(PathOperation.difference, path, hole);
  }

  @override
  bool shouldReclip(covariant _TagHoleClipper oldClipper) => false;
}
