import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'scroll_reveal.dart';
import 'ticket.dart' show MiniTicketChip;
import 'watched_preview_sheet.dart';

/// The Diary tab's centerpiece in the "Cinema" theme — a little marquee
/// sign whose bulbs light up as evenings get logged, the same "mood, not
/// a data table" teaser language as [RouteBoard]'s road and [GardenBox]'s
/// window box (see evening_road.dart / garden_bed.dart). A tap flickers
/// the bulbs on and opens the full programme — every evening printed as
/// a proper screening card (poster, screen, seat, showtime), the same
/// beat as those themes' stop/bloom cards — rather than a string of
/// tickets pegged to a washing line.
class TicketJar extends StatefulWidget {
  final List<DiaryEntry> entries;
  const TicketJar({super.key, required this.entries});

  @override
  State<TicketJar> createState() => _TicketJarState();
}

class _TicketJarState extends State<TicketJar> with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy || widget.entries.isEmpty) return;
    setState(() => _busy = true);
    await _flicker.forward(from: 0);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: CinemaProgrammeScreen(entries: widget.entries),
        ),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.entries.isEmpty;
    // Grows (capped at the fixed number of bulbs) with the real log, so
    // the sign visibly lights up further over weeks, without pretending
    // it's a literal one-bulb-per-evening count — same restraint as the
    // road's dots and the window box's blooms.
    final litCount = isEmpty ? 0 : math.min(2 + widget.entries.length, _MarqueeSign.bulbCount);
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 172,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _flicker,
                builder: (context, child) => _MarqueeSign(
                  litCount: litCount,
                  flicker: _flicker.value,
                  entries: widget.entries,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEmpty
                  ? 'an empty marquee, waiting'
                  : '${widget.entries.length} ${widget.entries.length == 1 ? 'evening' : 'evenings'}, up on the marquee',
              style: SeenlyText.serif(italic: true, size: 19),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 12, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 5),
                Text(
                  isEmpty ? 'log one to light the first bulb' : "tap for tonight's full programme",
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small theater marquee: a dark arched canopy with a scalloped
/// underside, a row of bulbs that light up as more evenings get logged,
/// and a slim shelf of ticket-stub chips standing in for tonight's box
/// office queue — sampled from the real log's ratings, same "spread
/// across the log rather than a fixed handful" trick the clothesline
/// used to use. [flicker] (0..1) sends a quick spark sweeping left to
/// right across the lit bulbs on tap, before the full programme opens.
class _MarqueeSign extends StatelessWidget {
  static const bulbCount = 9;

  final int litCount;
  final double flicker;
  final List<DiaryEntry> entries;

  const _MarqueeSign({required this.litCount, required this.flicker, required this.entries});

  Color _stubColor(int i) {
    if (entries.isEmpty) {
      const fallback = [
        SeenlyPalette.coral,
        SeenlyPalette.periwinkle,
        SeenlyPalette.accent,
        SeenlyPalette.mustard,
        SeenlyPalette.cork,
      ];
      return fallback[i % fallback.length];
    }
    final idx = (i * entries.length / 5).floor().clamp(0, entries.length - 1);
    final rating = entries[idx].rating;
    return rating != null ? SeenlyPalette.ratingColor(rating) : SeenlyPalette.cork;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final canopyHeight = size.height * 0.56;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(size.width, canopyHeight),
              painter: const _CanopyPainter(),
            ),
            for (int i = 0; i < bulbCount; i++) _bulb(size.width, canopyHeight, i),
            Positioned(
              left: 0,
              right: 0,
              top: canopyHeight * 0.32,
              child: Center(
                child: Text(
                  'NOW SHOWING',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.mustard.withOpacity(0.85), weight: FontWeight.w700),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: size.height - canopyHeight - 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Transform.rotate(
                        angle: (i.isEven ? -1 : 1) * 0.05,
                        child: MiniTicketChip(
                          color: _stubColor(i),
                          width: 18,
                          height: 26 + (i.isOdd ? 8 : 0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bulb(double width, double canopyHeight, int i) {
    final t = bulbCount == 1 ? 0.0 : i / (bulbCount - 1);
    final x = 10 + t * (width - 20);
    final y = canopyHeight * 0.62;
    final lit = i < litCount;
    // The spark sweeps across all nine slots regardless of which are
    // actually lit — an unlit bulb still gets a faint flash of life as
    // the wave passes, the way a real marquee flickers before settling.
    final localFlicker = ((flicker * (bulbCount + 3)) - i).clamp(0.0, 1.0);
    final spark = (1 - ((localFlicker - 0.5).abs() * 2.4).clamp(0.0, 1.0));
    final baseGlow = lit ? 0.85 : 0.0;
    final glow = (baseGlow + spark * 0.5).clamp(0.0, 1.0);
    final bulbColor = Color.lerp(SeenlyPalette.inkFaint.withOpacity(0.35), SeenlyPalette.mustard, glow)!;
    return Positioned(
      left: x - 5,
      top: y - 5,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bulbColor,
          boxShadow: glow > 0.15
              ? [BoxShadow(color: SeenlyPalette.mustard.withOpacity(glow * 0.55), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}

/// The marquee canopy itself: a dark rectangle with a scalloped bottom
/// edge, the way a real theater awning's underside is stitched into a
/// row of soft bumps rather than a straight hem.
class _CanopyPainter extends CustomPainter {
  const _CanopyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const scallops = 9;
    final scallopW = size.width / scallops;
    final flatY = size.height * 0.78;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, flatY);
    for (int i = scallops; i >= 1; i--) {
      final x1 = i * scallopW;
      final x0 = (i - 1) * scallopW;
      final midX = (x0 + x1) / 2;
      path.quadraticBezierTo(midX, flatY + scallopW * 0.5, x0, flatY);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = SeenlyPalette.ink..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _CanopyPainter oldDelegate) => false;
}

/// A ticket stub's screening details, generated deterministically from
/// the entry's own id — same "same seed, same result" spirit as
/// [routeForRuntime] in coach_routes.dart, just for a screen number, a
/// seat, and a runtime instead of a city pair.
class _Screening {
  final int screen;
  final String seatRow;
  final int seatNumber;
  final int minutes;
  const _Screening({required this.screen, required this.seatRow, required this.seatNumber, required this.minutes});
}

const Map<String, int> _fallbackMinutes = {
  'movie': 105,
  'series': 45,
  'anime': 24,
  'game': 150,
  'book': 240,
  'manga': 30,
};

// A modest spread of plausible session lengths, the same ballpark
// approach coach_routes.dart takes with its curated coach durations —
// close to tonight's actual runtime when known, picked from the
// nearest few rather than invented from nothing.
const List<int> _plausibleMinutes = [70, 85, 95, 100, 105, 110, 115, 120, 125, 130, 140, 150, 165, 180, 210];

_Screening _screeningFor(DiaryEntry entry) {
  const rows = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K'];
  final effective = _fallbackMinutes[entry.mediaType] ?? 100;
  final byCloseness = [..._plausibleMinutes]..sort((a, b) => (a - effective).abs().compareTo((b - effective).abs()));
  final pool = byCloseness.take(3).toList();
  final r = math.Random(entry.id.hashCode);
  return _Screening(
    screen: 1 + r.nextInt(9),
    seatRow: rows[r.nextInt(rows.length)],
    seatNumber: 1 + r.nextInt(22),
    minutes: pool[r.nextInt(pool.length)],
  );
}

const List<String> _screenMonths = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _screenDateLabel(DateTime d) => '${d.day} ${_screenMonths[d.month - 1]}';

IconData _screenMediaIcon(String mediaType) {
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

/// The full programme — every logged evening printed as a proper
/// screening card instead of a ticket hanging from a peg, mirroring
/// [EveningRoadScreen] and [GardenBedScreen] beat for beat so the three
/// themes read as the same app in different clothes.
class CinemaProgrammeScreen extends StatelessWidget {
  final List<DiaryEntry> entries;
  const CinemaProgrammeScreen({super.key, required this.entries});

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
                      Text('the programme', style: SeenlyText.serif(size: 20, weight: FontWeight.w600)),
                      Text(
                        '${entries.length} ${entries.length == 1 ? 'screening' : 'screenings'}',
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
                      child: const Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('nothing on the programme yet',
                          style: SeenlyText.serif(italic: true, color: SeenlyPalette.placeholder)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 60),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _ScreeningCard(
                        entry: entries[i],
                        index: i,
                        onTap: () => _openScreening(context, entries[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openScreening(BuildContext context, DiaryEntry entry) {
    showWatchedPreview(context, WatchedPreviewData.fromDiaryEntry(entry));
  }
}

/// One evening, printed like a little cinema ticket instead of a card
/// pegged to a line: a date and a "screened"/"rescreened" stamp up top,
/// tonight's screen and seat in big station-board type either side of a
/// dashed rail (this theme's answer to the train theme's route), the
/// poster riding along the left edge, then a footer with the runtime
/// and however many hearts the evening earned. Cards stack straight down
/// the page with a slight overlap, same trick as the other two themes'
/// stacks, rather than swinging from a cord.
class _ScreeningCard extends StatelessWidget {
  final DiaryEntry entry;
  final int index;
  final VoidCallback onTap;
  const _ScreeningCard({required this.entry, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screening = _screeningFor(entry);
    final categoryColor = SeenlyPalette.mediaColor(entry.mediaType);
    final statusColor = entry.isRewatch ? SeenlyPalette.mustard : SeenlyPalette.sage;
    final statusLabel = entry.isRewatch ? 'RESCREENED' : 'SCREENED';
    // A hair of tilt, alternating by index, so a stub doesn't look
    // machine-stamped — same trick the diary's scrapbook entries use,
    // kept small enough that the ticket copy stays fully readable.
    final angle = (index.isEven ? -1 : 1) * 0.012;

    return ScrollRevealEntrance(
      index: index,
      child: Transform.rotate(
        angle: angle,
        child: Transform.translate(
          offset: Offset(0, -12.0 * index),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(20),
                boxShadow: SeenlyPalette.softShadow,
                border: Border.all(color: SeenlyPalette.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 10.5, color: SeenlyPalette.inkFaint),
                          const SizedBox(width: 5),
                          Text(_screenDateLabel(entry.watchedAt),
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
                              child: _screenBlock('SCR ${screening.screen}', 'screen', alignEnd: false),
                            ),
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _ReelRail(color: categoryColor.withOpacity(0.55)),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: _screenBlock('${screening.seatRow}${screening.seatNumber}', 'seat', alignEnd: true),
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
                      Text(_durationLabel(screening.minutes),
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

  Widget _screenBlock(String code, String label, {required bool alignEnd}) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(code, style: SeenlyText.serif(size: 19, weight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(label, style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint)),
        ],
      );

  Widget _posterFallback(DiaryEntry entry, Color color) => Container(
        color: color,
        alignment: Alignment.center,
        child: Icon(_screenMediaIcon(entry.mediaType), size: 20, color: SeenlyPalette.paper),
      );

  static String _durationLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

/// The dashed rail between screen and seat, with a small reel riding
/// its midpoint — this theme's answer to the train theme's dotted
/// route line and the little train icon riding it.
class _ReelRail extends StatelessWidget {
  final Color color;
  const _ReelRail({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: CustomPaint(
        painter: _ReelRailPainter(color: color),
        child: Align(
          alignment: Alignment.center,
          child: Icon(Icons.theaters_outlined, size: 13, color: color),
        ),
      ),
    );
  }
}

class _ReelRailPainter extends CustomPainter {
  final Color color;
  const _ReelRailPainter({required this.color});

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
  bool shouldRepaint(covariant _ReelRailPainter oldDelegate) => oldDelegate.color != color;
}

/// A soft dashed rule used as the ticket's tear-line between the
/// screen/seat row and the footer — evenly spaced regardless of the
/// card's width.
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
