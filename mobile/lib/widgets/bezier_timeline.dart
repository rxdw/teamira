import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'watched_preview_sheet.dart';
import '../services/app_translations.dart';

/// One entry on the timeline. `isRight` is a property of the data, not a
/// computed index%2 — the side is decided per event (alternating watch vs.
/// rewatch, see [RewatchTimeline.fromDiaryEntries]), so the shape of the
/// line is intentional, not automatic alternation.
class TimelineItem {
  final DateTime date;
  final String description;
  final bool isRight;
  final VoidCallback? onTap;

  const TimelineItem({
    required this.date,
    required this.description,
    this.isRight = true,
    this.onTap,
  });
}

/// Adapts a title's [DiaryEntry] history (oldest first, as returned by
/// `GET /diary/media/{id}`) into a [BezierTimeline]. First watch and every
/// rewatch alternate sides purely so consecutive cards don't stack directly
/// on top of one another — the thread itself is what carries the "these
/// are all the same story" feeling.
class RewatchTimeline extends StatelessWidget {
  final List<DiaryEntry> entries;
  // Called after a card's preview sheet closes — the person may have
  // edited that evening's rating/review inside it, so the caller gets a
  // chance to re-fetch (see TitleDetailScreen._refreshHistory).
  final VoidCallback? onEntryChanged;
  const RewatchTimeline({super.key, required this.entries, this.onEntryChanged});

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  String _describe(DiaryEntry e, int index) {
    if (index == 0) return 'first watch';
    if (e.note != null && e.note!.trim().isNotEmpty) return e.note!.trim();
    if (e.moodTags.isNotEmpty) return e.moodTags.first;
    return 'watched again';
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(
        'no evenings logged yet for this title'.tr,
        style: SeenlyText.serif(color: SeenlyPalette.placeholder, italic: true),
      );
    }

    final items = <TimelineItem>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      items.add(TimelineItem(
        date: e.watchedAt,
        description: _describe(e, i),
        isRight: i.isEven,
        onTap: () async {
          await showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(e));
          onEntryChanged?.call();
        },
      ));
    }

    return BezierTimeline(items: items, monthLabels: _months);
  }
}

/// A vertical timeline where a single thread is drawn through the exact
/// center of every event's dot using consecutive cubic Bezier segments (no
/// sin/cos — the left/right rhythm comes entirely from [TimelineItem.isRight]).
/// Cards are tucked above and toward the inner side of each dot so the
/// thread never crosses their content.
///
/// Unlike a standalone screen version, this one does **not** wrap itself in
/// a `SingleChildScrollView` — it reports its own fixed height and expects
/// to sit inside a scroll view the caller already owns (the title detail
/// screen), matching how the rest of that screen scrolls as one page.
class BezierTimeline extends StatelessWidget {
  final List<TimelineItem> items;
  final List<String> monthLabels;
  final Color lineColor;
  final Color cardColor;
  final Color textColor;
  final Color secondaryTextColor;
  final double amplitude;

  const BezierTimeline({
    super.key,
    required this.items,
    required this.monthLabels,
    this.lineColor = SeenlyPalette.accent,
    this.cardColor = SeenlyPalette.paper,
    this.textColor = SeenlyPalette.ink,
    this.secondaryTextColor = SeenlyPalette.inkFaint,
    this.amplitude = 52,
  });

  static const double _margin = 12;
  static const double _cardPadding = 10;
  static const double _horizontalInset = 14;
  static const double _gapAboveNode = 14;
  static const double _rowSpacing = 30;
  static const double _dotRadius = 5;

  static TextStyle _dateStyle(Color color) =>
      SeenlyText.mono(size: 10, color: color, weight: FontWeight.w600);
  static TextStyle _descStyle(Color color) =>
      SeenlyText.serif(size: 12.5, italic: true, color: color, weight: FontWeight.w400);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final nodes = _layout(width);
        final totalHeight = nodes.isEmpty ? 0.0 : nodes.last.center.dy + _margin;

        return SizedBox(
          width: width,
          height: totalHeight,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(width, totalHeight),
                painter: _BezierLinePainter(
                  points: nodes.map((n) => n.center).toList(),
                  color: lineColor,
                ),
              ),
              for (final node in nodes) ...[
                _buildCard(node),
                _buildDot(node),
              ],
            ],
          ),
        );
      },
    );
  }

  List<_TimelineNode> _layout(double width) {
    final centerX = width / 2;
    final rightX = centerX + amplitude;
    final leftX = centerX - amplitude;
    final cardWidth =
        (centerX - amplitude - _margin - _horizontalInset).clamp(100.0, 190.0);

    final nodes = <_TimelineNode>[];
    double y = _margin;

    for (final item in items) {
      final nodeX = item.isRight ? rightX : leftX;

      final descPainter = TextPainter(
        text: TextSpan(text: item.description, style: _descStyle(textColor)),
        maxLines: 3,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cardWidth - _cardPadding * 2);

      double cardHeight = _cardPadding * 2;
      cardHeight += _dateStyle(secondaryTextColor).fontSize! * 1.2;
      cardHeight += 4;
      cardHeight += descPainter.height;

      final cardTop = y;
      final cardLeft = item.isRight
          ? nodeX - _horizontalInset - cardWidth
          : nodeX + _horizontalInset;

      final nodeY = cardTop + cardHeight + _gapAboveNode;

      nodes.add(_TimelineNode(
        item: item,
        center: Offset(nodeX, nodeY),
        cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
      ));

      y = nodeY + _rowSpacing;
    }

    return nodes;
  }

  Widget _buildDot(_TimelineNode node) {
    return Positioned(
      left: node.center.dx - _dotRadius,
      top: node.center.dy - _dotRadius,
      child: Container(
        width: _dotRadius * 2,
        height: _dotRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lineColor,
          border: Border.all(color: SeenlyPalette.background, width: 2),
        ),
      ),
    );
  }

  Widget _buildCard(_TimelineNode node) {
    final item = node.item;
    return Positioned(
      left: node.cardRect.left,
      top: node.cardRect.top,
      width: node.cardRect.width,
      child: GestureDetector(
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(_cardPadding),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatDate(item.date), style: _dateStyle(secondaryTextColor)),
              const SizedBox(height: 4),
              Text(
                item.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _descStyle(textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day} ${monthLabels[d.month - 1]}';
}

class _TimelineNode {
  final TimelineItem item;
  final Offset center;
  final Rect cardRect;
  const _TimelineNode({required this.item, required this.center, required this.cardRect});
}

/// Draws one continuous thread through every node center using a cubic
/// Bezier segment between each consecutive pair — no sin/cos anywhere, the
/// curve's shape is driven entirely by where the nodes actually are.
class _BezierLinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  const _BezierLinePainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midY = (p0.dy + p1.dy) / 2;
      path.cubicTo(p0.dx, midY, p1.dx, midY, p1.dx, p1.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BezierLinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
