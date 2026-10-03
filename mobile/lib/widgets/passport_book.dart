import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'stamp.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// The Diary tab's centerpiece in the passport theme — the counterpart
/// to `TicketJar`: a small closed passport sitting on the shelf instead
/// of a jar. A tap riffles the pages open into every stamp collected so
/// far, the way a jar gets a shake before it spills its tickets out.
class PassportBook extends StatefulWidget {
  final List<DiaryEntry> entries;
  const PassportBook({super.key, required this.entries});

  @override
  State<PassportBook> createState() => _PassportBookState();
}

class _PassportBookState extends State<PassportBook> with SingleTickerProviderStateMixin {
  late final AnimationController _riffle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _riffle = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  }

  @override
  void dispose() {
    _riffle.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy || widget.entries.isEmpty) return;
    setState(() => _busy = true);
    await _riffle.forward(from: 0);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: PassportSpreadView(entries: widget.entries),
        ),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _riffle,
              builder: (context, child) => _PassportCover(riffle: _riffle.value, entries: widget.entries),
            ),
            const SizedBox(height: 18),
            Text(
              widget.entries.isEmpty
                  ? 'a blank passport, waiting'
                  : '${widget.entries.length} ${widget.entries.length == 1 ? 'evening' : 'evenings'}, stamped',
              style: SeenlyText.serif(italic: true, size: 19),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 12, color: SeenlyPalette.inkFaint),
                const SizedBox(width: 5),
                Text(
                  widget.entries.isEmpty ? 'log one to see it land' : 'give it a flip to see them all',
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

/// The passport itself: a small leather-toned book with a crest on the
/// cover, sitting on a soft shelf glow. A handful of real stamps peek
/// from its fanned page-edges — a quiet preview of what's inside,
/// like a jar's tickets visible through the glass.
class _PassportCover extends StatelessWidget {
  final double riffle; // 0..1, plays once per tap
  final List<DiaryEntry> entries;
  const _PassportCover({required this.riffle, required this.entries});

  static const double _w = 138;
  static const double _h = 176;

  @override
  Widget build(BuildContext context) {
    // A quick riffle-tilt — the cover rocks open-and-shut once, like
    // pages being fanned with a thumb, before the spread view appears.
    final tilt = math.sin(riffle * math.pi * 3) * 0.05 * (1 - riffle);
    final peekCount = entries.isEmpty ? 0 : entries.length.clamp(1, 5).toInt();

    return SizedBox(
      width: _w + 40,
      height: _h + 22,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // soft warm shelf glow behind the book
          Positioned(
            top: 14,
            child: Container(
              width: _w + 34,
              height: _h - 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SeenlyPalette.mustard.withOpacity(0.15),
                    SeenlyPalette.mustard.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // shadow on the "shelf"
          Positioned(
            bottom: 0,
            child: Container(
              width: _w * 0.72,
              height: 12,
              decoration: BoxDecoration(
                color: SeenlyPalette.ink.withOpacity(0.14),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          // fanned page edges, peeking out from behind the cover
          for (int i = 0; i < peekCount; i++)
            Positioned(
              top: 12 + i * 1.6,
              child: Transform.rotate(
                angle: stampJitter(entries[i].id, -0.05, 0.05, salt: 4),
                child: Container(
                  width: _w * 0.86,
                  height: _h * 0.78,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: SeenlyPalette.border, width: 1),
                  ),
                ),
              ),
            ),
          // the cover itself
          Positioned(
            top: 10,
            child: Transform.rotate(
              angle: tilt,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: _w,
                height: _h,
                decoration: BoxDecoration(
                  color: SeenlyPalette.ink,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: SeenlyPalette.ink.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
                ),
                child: Stack(
                  children: [
                    // spine shadow along the left edge
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 10, color: Colors.black.withOpacity(0.16)),
                    ),
                    Center(
                      child: _GoldEmboss(
                        // The tilt already rocks between roughly -0.05
                        // and 0.05 as the cover riffles — mapped to 0..1
                        // here, a bright streak of shine sweeps across
                        // the gilt exactly as if catching real light off
                        // foil-stamped lettering as the book turns.
                        shine: 0.5 + (tilt / 0.05).clamp(-1.0, 1.0) * 0.5,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Crest(),
                            const SizedBox(height: 10),
                            Text('SEENLY'.tr,
                                style: SeenlyText.mono(
                                    size: 9, color: SeenlyPalette.mustard, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A streak of bright gold sweeping across whatever it wraps — the
/// "foil catching the light" beat for the passport cover's tooled
/// title, tied directly to the cover's own tilt rather than looping on
/// its own, so it genuinely reads as a reflection rather than a
/// decorative animation bolted on beside it.
class _GoldEmboss extends StatelessWidget {
  final double shine; // 0..1, where the bright streak currently sits
  final Widget child;

  const _GoldEmboss({required this.shine, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = shine.clamp(0.0, 1.0);
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(1, 1),
          colors: [
            SeenlyPalette.mustard.withOpacity(0.55),
            SeenlyPalette.paper,
            SeenlyPalette.mustard.withOpacity(0.55),
          ],
          stops: [(c - 0.35).clamp(0.0, 1.0), c, (c + 0.35).clamp(0.0, 1.0)],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// A small crest standing in for the gilt emblem on a real passport's
/// cover — a ringed circle with a diamond at its heart, built from
/// plain shapes rather than a system icon, same paper-cut spirit as
/// the ticket theme's hand-drawn seat.
class _Crest extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SeenlyPalette.mustard.withOpacity(0.6), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: SeenlyPalette.mustard.withOpacity(0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// The "riffled open" view — every logged evening, laid out as a grid
/// of stamps the way pages of a real passport line up in neat rows.
/// Entrance is staggered so it reads as pages turning past rather than
/// popping in as one flat grid.
class PassportSpreadView extends StatelessWidget {
  final List<DiaryEntry> entries;
  const PassportSpreadView({super.key, required this.entries});

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
                  Text('riffled open'.tr,
                      style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: SeenlyPalette.paper.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) => _SpreadStamp(
                  index: i,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TitleDetailScreen(
                          mediaId: entries[i].mediaId,
                          source: entries[i].source,
                          mediaType: entries[i].mediaType,
                          seedTitle: entries[i].displayTitle,
                          seedPosterUrl: entries[i].posterUrl,
                        ),
                      ),
                    ),
                    child: StampWidget(
                      title: entries[i].displayTitle,
                      mediaType: entries[i].mediaType,
                      rating: entries[i].rating,
                      watchedAt: entries[i].watchedAt,
                      size: 100,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpreadStamp extends StatefulWidget {
  final int index;
  final Widget child;
  const _SpreadStamp({required this.index, required this.child});

  @override
  State<_SpreadStamp> createState() => _SpreadStampState();
}

class _SpreadStampState extends State<_SpreadStamp> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index * 35).clamp(0, 700).toInt();
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _shown ? 1 : 0.6,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 240),
        child: widget.child,
      ),
    );
  }
}
