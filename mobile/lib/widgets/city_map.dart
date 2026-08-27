import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'building.dart';
import '../services/app_translations.dart';

/// The Diary tab's centerpiece in the city theme — the counterpart to
/// `TicketJar`/`PassportBook`/`RouteBoard`: a little skyline sitting on
/// the shelf instead of a jar, book, or board. A tap walks out onto the
/// full street — every evening you've logged, standing in the order you
/// watched them, left to right.
///
/// A full free-roam, pannable map would be the "true" version of this
/// idea; what's here is a scoped-down but still walkable version of the
/// same pitch — a street you scroll down rather than a city you pan
/// around — chosen so the skyline is something that actually ships and
/// holds up, not a promise of a map engine.
class CityMap extends StatelessWidget {
  final List<DiaryEntry> entries;
  const CityMap({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    // Oldest first, so walking the street left-to-right also walks
    // forward through time — the whole point of the theme.
    final chronological = [...entries]..sort((a, b) => a.watchedAt.compareTo(b.watchedAt));
    final preview = chronological.length <= 5 ? chronological : chronological.sublist(chronological.length - 5);

    return GestureDetector(
      onTap: entries.isEmpty
          ? null
          : () => Navigator.of(context).push(
                PageRouteBuilder(
                  opaque: false,
                  barrierColor: Colors.transparent,
                  transitionDuration: const Duration(milliseconds: 260),
                  pageBuilder: (_, anim, __) =>
                      FadeTransition(opacity: anim, child: CityStreetView(entries: chronological)),
                ),
              ),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _DuskSky(starCount: 14)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                children: [
                  SizedBox(
                    height: 118,
                    child: preview.isEmpty
                        ? Center(
                            child: Text('an empty lot, waiting'.tr,
                                style: SeenlyText.mono(size: 11, color: SeenlyPalette.paper.withOpacity(0.55))),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final entry in preview)
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3),
                                    child: BuildingWidget(
                                      title: entry.displayTitle,
                                      mediaType: entry.mediaType,
                                      rating: entry.rating,
                                      watchedAt: entry.watchedAt,
                                      width: 36,
                                      height: 96,
                                      showLabel: true,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        SeenlyPalette.mustard.withOpacity(0.0),
                        SeenlyPalette.mustard.withOpacity(0.45),
                        SeenlyPalette.mustard.withOpacity(0.0),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    entries.isEmpty
                        ? 'a skyline, waiting to start'
                        : '${entries.length} ${entries.length == 1 ? 'evening' : 'evenings'}, built',
                    style: SeenlyText.serif(italic: true, size: 19, color: SeenlyPalette.paper),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 12, color: SeenlyPalette.paper.withOpacity(0.5)),
                      const SizedBox(width: 5),
                      Text(
                        entries.isEmpty ? 'log one to see it rise' : 'walk the street to see them all',
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.paper.withOpacity(0.5)),
                      ),
                    ],
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

/// The full street — every logged evening, standing in watch order,
/// scrollable the way a real walk down a block is: one direction, at
/// your own pace, each building fading up as it comes into view.
class CityStreetView extends StatelessWidget {
  final List<DiaryEntry> entries; // already chronological, oldest first
  const CityStreetView({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _DuskSky(starCount: 40)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('your street'.tr,
                          style: SeenlyText.serif(italic: true, size: 18, color: SeenlyPalette.paper)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration:
                              BoxDecoration(color: SeenlyPalette.paper.withOpacity(0.9), shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 16, color: SeenlyPalette.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _StreetBuilding(index: i, entry: entries[i]),
                  ),
                ),
                Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      SeenlyPalette.mustard.withOpacity(0.0),
                      SeenlyPalette.mustard.withOpacity(0.4),
                      SeenlyPalette.mustard.withOpacity(0.0),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet dusk-toned backdrop — a gradient from deep ink down to a
/// warm horizon glow, a soft-haloed moon, and a scatter of stars that
/// actually twinkle — so a dark building silhouette has something
/// alive to stand out against, instead of a flat ink-colored card.
class _DuskSky extends StatefulWidget {
  final int starCount;
  const _DuskSky({required this.starCount});

  @override
  State<_DuskSky> createState() => _DuskSkyState();
}

class _DuskSkyState extends State<_DuskSky> with SingleTickerProviderStateMixin {
  late final AnimationController _loop;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _stars = _makeStars(widget.starCount);
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(() => setState(() {}))
      ..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  static List<_Star> _makeStars(int count) {
    final r = math.Random(0xD05C); // fixed seed — the same sky every time
    return List.generate(count, (_) {
      return _Star(
        x: r.nextDouble() * 400,
        y: r.nextDouble() * 90,
        size: 1.2 + r.nextDouble() * 1.7,
        baseOpacity: 0.22 + r.nextDouble() * 0.35,
        phase: r.nextDouble(),
        speed: 0.5 + r.nextDouble() * 1.1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            SeenlyPalette.ink,
            Color.lerp(SeenlyPalette.ink, SeenlyPalette.mustard, 0.14)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: 28, top: 12, child: _MoonGlow(loop: _loop.value)),
          for (final s in _stars)
            Positioned(
              left: s.x,
              top: s.y,
              child: Container(
                width: s.size,
                height: s.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeenlyPalette.paper.withOpacity(
                    (s.baseOpacity *
                            (0.35 +
                                0.65 *
                                    ((math.sin((_loop.value * s.speed + s.phase) * 2 * math.pi) + 1) / 2)))
                        .clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double size;
  final double baseOpacity;
  final double phase;
  final double speed;

  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.baseOpacity,
    required this.phase,
    required this.speed,
  });
}

/// A small moon with a soft, gently breathing halo — the sky's one
/// fixed light source, so the twinkling stars read as scattered around
/// something rather than floating in an empty gradient.
class _MoonGlow extends StatelessWidget {
  final double loop; // 0..1, shared with the stars' twinkle
  const _MoonGlow({required this.loop});

  @override
  Widget build(BuildContext context) {
    final breathe = 0.55 + 0.45 * ((math.sin(loop * 2 * math.pi * 0.4) + 1) / 2);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SeenlyPalette.paper.withOpacity(0.92),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.paper.withOpacity(0.22 * breathe), blurRadius: 24, spreadRadius: 9),
          BoxShadow(color: SeenlyPalette.paper.withOpacity(0.4 * breathe), blurRadius: 10, spreadRadius: 1),
        ],
      ),
    );
  }
}

class _StreetBuilding extends StatefulWidget {
  final int index;
  final DiaryEntry entry;
  const _StreetBuilding({required this.index, required this.entry});

  @override
  State<_StreetBuilding> createState() => _StreetBuildingState();
}

class _StreetBuildingState extends State<_StreetBuilding> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index * 25).clamp(0, 900).toInt();
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.15),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 280),
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
            child: BuildingWidget(
              title: entry.displayTitle,
              mediaType: entry.mediaType,
              rating: entry.rating,
              watchedAt: entry.watchedAt,
              width: 58,
              height: 210,
              showLabel: true,
            ),
          ),
        ),
      ),
    );
  }
}
