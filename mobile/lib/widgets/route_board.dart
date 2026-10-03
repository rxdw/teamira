import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/coach_routes.dart';
import '../models/diary_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'boarding_pass.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// The Diary tab's centerpiece in the "Evening Route" theme — the
/// counterpart to `TicketJar`: a small split-flap
/// departures board instead of a jar or a book. A tap flips every row
/// over to reveal the full manifest of evenings logged so far, the way
/// a jar gets a shake and a passport gets a riffle.
class RouteBoard extends StatefulWidget {
  final List<DiaryEntry> entries;
  const RouteBoard({super.key, required this.entries});

  @override
  State<RouteBoard> createState() => _RouteBoardState();
}

class _RouteBoardState extends State<RouteBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _busy = false;

  static const _rowCount = 4;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy || widget.entries.isEmpty) return;
    setState(() => _busy = true);
    await _flip.forward(from: 0);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: RouteManifestView(entries: widget.entries)),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final recent = widget.entries.take(_rowCount).toList();
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.ink,
          borderRadius: BorderRadius.circular(20),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('DEPARTURES'.tr,
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.mustard.withOpacity(0.8), weight: FontWeight.w700)),
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.mustard.withOpacity(0.7)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              _BoardRow(left: 'a blank board', right: 'waiting', flip: 0, delay: 0)
            else
              for (int i = 0; i < recent.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AnimatedBuilder(
                    animation: _flip,
                    builder: (context, _) => _BoardRow(
                      left: recent[i].displayTitle,
                      right: _routeSuffix(recent[i]),
                      flip: _flip.value,
                      delay: i * 0.12,
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 12, color: SeenlyPalette.mustard.withOpacity(0.6)),
                const SizedBox(width: 5),
                Text(
                  widget.entries.isEmpty ? 'log one to see it posted' : 'tap for the full manifest',
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.mustard.withOpacity(0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _routeSuffix(DiaryEntry entry) {
    final route = routeForRuntime(runtimeMinutes: null, mediaType: entry.mediaType, seed: entry.id);
    return route.destCode;
  }
}

/// One split-flap row: a title on the left, a destination code on the
/// right, each character flipping into place with a short staggered
/// delay — the mechanical clatter of a real station board, softened
/// into a single quick settle rather than a true per-character churn.
class _BoardRow extends StatelessWidget {
  final String left;
  final String right;
  final double flip; // 0..1, shared across the board, offset per-row by [delay]
  final double delay;

  const _BoardRow({required this.left, required this.right, required this.flip, required this.delay});

  @override
  Widget build(BuildContext context) {
    final local = ((flip - delay) / (1 - delay)).clamp(0.0, 1.0);
    final eased = Curves.easeOut.transform(local);
    // A quick vertical squash right as the flap "lands," rather than a
    // smooth glide the whole way — mechanical, not silky.
    final squash = 1 - 0.5 * math.sin(local.clamp(0.0, 0.4) / 0.4 * math.pi);
    // A brief white flash timed to the same landing instant — the
    // little spark of a real split-flap's leaf clacking into place.
    final click = local <= 0 || local >= 1
        ? 0.0
        : (1 - ((local - 0.4).abs() / 0.16).clamp(0.0, 1.0)).toDouble();

    return Opacity(
      opacity: 0.35 + 0.65 * eased,
      child: Transform.scale(
        scaleY: squash,
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(right,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.mustard, weight: FontWeight.w700)),
              ],
            ),
            if (click > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: SeenlyPalette.paper.withOpacity(click * 0.4)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The full manifest — every logged evening, laid out as boarding
/// passes the way a station's printed schedule lines up its rows.
class RouteManifestView extends StatelessWidget {
  final List<DiaryEntry> entries;
  const RouteManifestView({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.ink.withOpacity(0.32),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('full manifest'.tr, style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: SeenlyPalette.paper.withOpacity(0.9), shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(18),
                itemCount: entries.length,
                itemBuilder: (context, i) => _ManifestRow(index: i, entry: entries[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManifestRow extends StatefulWidget {
  final int index;
  final DiaryEntry entry;
  const _ManifestRow({required this.index, required this.entry});

  @override
  State<_ManifestRow> createState() => _ManifestRowState();
}

class _ManifestRowState extends State<_ManifestRow> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index * 45).clamp(0, 700).toInt();
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(-0.06, 0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TitleDetailScreen(
                  mediaId: entry.mediaId,
                  source: entry.source,
                  mediaType: entry.mediaType,
                  seedTitle: entry.displayTitle,
                  seedPosterUrl: entry.posterUrl,
                ),
              ),
            ),
            child: BoardingPassWidget(
              title: entry.displayTitle,
              mediaType: entry.mediaType,
              rating: entry.rating,
              watchedAt: entry.watchedAt,
              width: 260,
              height: 104,
              compact: false,
            ),
          ),
        ),
      ),
    );
  }
}
