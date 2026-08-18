import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';

/// One selectable content category — movies, series, anime, games, books,
/// manga. Shared between [CollectionInterestsScreen] and the onboarding
/// flow so the two pickers can never quietly drift apart.
class Interest {
  final String value;
  final String label;
  final String hint;
  final IconData icon;
  final bool soon;
  const Interest({
    required this.value,
    required this.label,
    required this.hint,
    required this.icon,
    this.soon = false,
  });
}

const kInterests = [
  Interest(
    value: 'movie',
    label: 'movies',
    hint: 'evenings at the cinema, rewatches, the classics',
    icon: Icons.local_movies_outlined,
  ),
  Interest(
    value: 'series',
    label: 'series',
    hint: 'season by season, whatever\'s airing tonight',
    icon: Icons.tv_outlined,
  ),
  Interest(
    value: 'anime',
    label: 'anime',
    hint: 'shows you\'re marathoning, new episodes as they land',
    icon: Icons.movie_filter_outlined,
  ),
  Interest(
    value: 'game',
    label: 'games',
    hint: 'what you\'re playing, or about to start',
    icon: Icons.sports_esports_outlined,
  ),
  Interest(
    value: 'book',
    label: 'books',
    hint: 'whatever you\'re reading, page by page',
    icon: Icons.menu_book_outlined,
  ),
  Interest(
    value: 'manga',
    label: 'manga',
    hint: 'volumes and chapters, one at a time',
    icon: Icons.auto_stories_outlined,
  ),
];

/// A single tappable interest row: colored spine, faint category motif
/// bleeding off the right edge, label + hint, and a check circle. Used at
/// full size in [CollectionInterestsScreen] and at the same size inside
/// onboarding's interests step, so the two pickers feel identical.
class InterestPickerRow extends StatelessWidget {
  final Interest interest;
  final bool selected;
  final VoidCallback? onTap;

  const InterestPickerRow({super.key, required this.interest, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = SeenlyPalette.mediaColor(interest.value);
    final content = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: interest.soon
            ? Colors.transparent
            : (selected ? color.withOpacity(0.12) : SeenlyPalette.paper),
        borderRadius: BorderRadius.circular(14),
        border: selected
            ? Border.all(color: color, width: 1.2)
            : (interest.soon ? null : Border.all(color: SeenlyPalette.border)),
      ),
      child: Stack(
        children: [
          if (!interest.soon)
            Positioned(
              right: -10,
              top: -14,
              bottom: -14,
              width: 108,
              child: CustomPaint(
                painter: InterestMotifPainter(
                  value: interest.value,
                  color: color,
                  opacity: selected ? 0.16 : 0.09,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  decoration: BoxDecoration(
                    color: interest.soon ? SeenlyPalette.dashedBorder : color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(interest.label.tr,
                              style: SeenlyText.cardTitle.copyWith(
                                color: interest.soon ? SeenlyPalette.placeholder : SeenlyPalette.ink,
                              )),
                          if (interest.soon) ...[
                            const SizedBox(width: 8),
                            PillChip(label: 'soon'.tr, dashed: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(interest.hint.tr,
                          style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                    ],
                  ),
                ),
                if (!interest.soon) ...[
                  const SizedBox(width: 8),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color: selected ? color : SeenlyPalette.dashedBorder,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (interest.soon) return DashedBox(radius: 14, child: content);
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// A faint, category-shaped scribble sitting in the background of each
/// row — a filmstrip, a screen, a burst of speed lines, a d-pad, an open
/// book, a scatter of screentone dots — so the card reads as "about
/// movies" or "about manga" at a glance, without another icon badge.
/// Also reused, larger and fainter, as scattered decoration behind the
/// onboarding welcome step.
class InterestMotifPainter extends CustomPainter {
  final String value;
  final Color color;
  final double opacity;
  const InterestMotifPainter({required this.value, required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color.withOpacity(opacity);

    switch (value) {
      case 'movie':
        _filmstrip(canvas, size, stroke, fill);
        break;
      case 'series':
        _screen(canvas, size, stroke, fill);
        break;
      case 'anime':
        _burst(canvas, size, stroke);
        break;
      case 'game':
        _gamepad(canvas, size, stroke, fill);
        break;
      case 'book':
        _bookStack(canvas, size, stroke, fill);
        break;
      case 'manga':
        _screentone(canvas, size, fill);
        break;
    }
  }

  void _filmstrip(Canvas canvas, Size size, Paint stroke, Paint fill) {
    canvas.save();
    canvas.translate(size.width * 0.56, size.height * 0.5);
    canvas.rotate(-0.4);
    canvas.translate(-size.width * 0.56, -size.height * 0.5);
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.56, size.height * 0.5),
      width: size.width * 0.95,
      height: size.height * 0.5,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), stroke);
    const holes = 5;
    final gap = rect.width / holes;
    for (int i = 0; i < holes; i++) {
      final cx = rect.left + gap * i + gap * 0.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, rect.top + 6), width: gap * 0.32, height: 7),
          const Radius.circular(1.5),
        ),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, rect.bottom - 6), width: gap * 0.32, height: 7),
          const Radius.circular(1.5),
        ),
        fill,
      );
    }
    canvas.restore();
  }

  void _screen(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.58, size.height * 0.46),
      width: size.width * 0.78,
      height: size.height * 0.5,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), stroke);
    canvas.drawLine(
      Offset(rect.left + 14, rect.center.dy),
      Offset(rect.right - 14, rect.center.dy),
      stroke..strokeWidth = 1.6,
    );
    canvas.drawLine(Offset(rect.center.dx - 10, rect.bottom), Offset(rect.center.dx - 18, rect.bottom + 12), stroke);
    canvas.drawLine(Offset(rect.center.dx + 10, rect.bottom), Offset(rect.center.dx + 18, rect.bottom + 12), stroke);
  }

  void _burst(Canvas canvas, Size size, Paint stroke) {
    final center = Offset(size.width * 0.56, size.height * 0.48);
    for (int i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * math.pi;
      final inner = i.isEven ? 10.0 : 18.0;
      final outer = i.isEven ? 30.0 : 22.0;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * outer,
        stroke,
      );
    }
  }

  void _gamepad(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final cx = size.width * 0.56;
    final cy = size.height * 0.5;
    const bodyW = 76.0, bodyH = 36.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: bodyW, height: bodyH),
      const Radius.circular(18),
    );
    canvas.drawRRect(body, stroke..strokeWidth = 2.4);

    final dpadC = Offset(cx - bodyW * 0.24, cy);
    const arm = 7.5, thick = 6.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: dpadC, width: arm * 2 + thick, height: thick),
        const Radius.circular(1.5),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: dpadC, width: thick, height: arm * 2 + thick),
        const Radius.circular(1.5),
      ),
      fill,
    );

    final btnC = Offset(cx + bodyW * 0.28, cy);
    for (final o in [const Offset(-8, 0), const Offset(8, 0), const Offset(0, -8), const Offset(0, 8)]) {
      canvas.drawCircle(btnC + o, 4.5, fill);
    }
  }

  void _bookStack(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final cx = size.width * 0.56;
    const widths = [60.0, 46.0, 54.0];
    const heights = [11.0, 11.0, 11.0];
    const gap = 5.0;
    double y = size.height * 0.68;
    double topOfStack = y;
    for (int i = 0; i < widths.length; i++) {
      final rect = Rect.fromCenter(center: Offset(cx, y), width: widths[i], height: heights[i]);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), fill);
      topOfStack = y - heights[i] / 2;
      y -= heights[i] + gap;
    }
    canvas.drawLine(
      Offset(cx - widths.last * 0.28, topOfStack),
      Offset(cx - widths.last * 0.28, topOfStack - 16),
      stroke..strokeWidth = 2.4,
    );
  }

  void _screentone(Canvas canvas, Size size, Paint fill) {
    const cols = 6, rows = 7;
    final left = size.width * 0.30;
    final right = size.width * 0.96;
    final top = size.height * 0.10;
    final bottom = size.height * 0.90;
    final colGap = (right - left) / (cols - 1);
    final rowGap = (bottom - top) / (rows - 1);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final t = (r / (rows - 1) + c / (cols - 1)) / 2;
        canvas.drawCircle(
          Offset(left + colGap * c, top + rowGap * r),
          1.0 + t * 2.6,
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant InterestMotifPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.opacity != opacity || oldDelegate.color != color;
}
