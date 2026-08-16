import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart';
import '../title/title_detail_screen.dart';
import '../../services/app_translations.dart';

enum _Phase { idle, spinning, landed }

/// The "spin the reel" decision method — a vertical column of big
/// posters that spins past a fixed center pointer and eases to a stop,
/// same deceleration language as everything else in the app that
/// settles into place rather than just appearing. The landing item is
/// picked with [math.Random] the moment a spin starts, same as the plain
/// random-pick screen — the reel is just a more ceremonial way of
/// watching that choice happen. Once it lands, though, the choice isn't
/// final: the reel becomes a normal scrollable list and any poster can
/// be tapped to become the pick instead, re-centering under the pointer
/// frame just like a landed spin would.
///
/// Vertical and sized to actually fill the screen rather than a thin
/// horizontal strip floating in the middle of a lot of empty paper —
/// each poster is big enough to read at a glance, faded at the top/
/// bottom edges of the reel so it reads as an endless column rather
/// than a hard-clipped list. Posters use the same fade-in loader as the
/// random-pick screen, so a tile never sits blank while its image is
/// still downloading — it shows its colored type icon immediately and
/// crossfades once the poster actually arrives.
class DecideRouletteScreen extends StatefulWidget {
  final List<MediaItem> pool;
  // Same override point as DecideRandomScreen's own [onSecondary] — see
  // its doc. Reused as-is for co-viewing's "spin the reel" (see
  // co_view_pick_screens.dart), swapping the landed pick's secondary
  // button from "plan to watch" to proposing it to the whole circle.
  final Future<MediaItem?> Function(BuildContext context, MediaItem item)? onSecondary;
  final String secondaryLabel;
  final String secondaryDoneLabel;
  final IconData secondaryIcon;
  final IconData secondaryDoneIcon;

  const DecideRouletteScreen({
    super.key,
    required this.pool,
    this.onSecondary,
    this.secondaryLabel = 'plan to watch',
    this.secondaryDoneLabel = 'added',
    this.secondaryIcon = Icons.bookmark_add_outlined,
    this.secondaryDoneIcon = Icons.bookmark,
  });

  @override
  State<DecideRouletteScreen> createState() => _DecideRouletteScreenState();
}

class _DecideRouletteScreenState extends State<DecideRouletteScreen> {
  // True poster ratio (2:3), sized responsively off screen width in build().
  static const _posterRatio = 1.5; // height / width
  static const _itemGap = 22.0;
  static double get _extent => _itemHeight + _itemGap;
  static double _itemWidth = 210.0;
  static double get _itemHeight => _itemWidth * _posterRatio;

  // The two flanking columns of small, dimmed, blurred posters that keep
  // the reel from reading as one thin column adrift in a lot of empty
  // paper. They're decorative only — same underlying pool, just a second
  // (and third) shuffle so they don't mirror the center column — and they
  // scroll in parallax off the *same* controller instead of animating
  // independently, so they never fall out of sync with the real spin.
  static const _ghostGap = 14.0;
  static const _ghostRatio = 1.5;
  static const _leftFactor = 0.62;
  static const _rightFactor = 0.46;

  final _controller = ScrollController();
  final _rnd = math.Random();
  double _viewportHeight = 480;
  List<MediaItem> _ghostLeft = const [];
  List<MediaItem> _ghostRight = const [];

  _Phase _phase = _Phase.idle;
  List<MediaItem> _reel = const [];
  MediaItem? _result;
  int? _resultIndex;
  bool _addingToPlan = false;
  bool _addedToPlan = false;

  // Once the reel lands, it's still just a scroll position — the person can
  // browse past it and tap any other poster to pick that one instead. Shown
  // once per landing, dismissed the moment they act on it (or after a bit,
  // so it never overstays).
  bool _showBrowseHint = false;

  // Warms Flutter's own image cache with every poster in the pool the
  // moment this screen opens — before the person has even tapped "Spin".
  // Without this, a fast-spinning reel built straight from network images
  // shows a lot of blank placeholder icons crossfading in mid-motion,
  // because ListView only starts each tile's Image.network download once
  // that tile is actually built/scrolled into view — too late to look
  // good at spin speed. precacheImage puts the same ImageProvider
  // Image.network would use into the cache ahead of time, so by the time
  // a tile is built during the spin it's usually a cache hit (synchronous,
  // no crossfade) rather than a cold network fetch. Guarded so it only
  // runs once per screen instance, not on every rebuild.
  bool _posterPrecacheStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_posterPrecacheStarted) {
      _posterPrecacheStarted = true;
      _precachePosters();
    }
  }

  void _precachePosters() {
    for (final item in widget.pool) {
      final url = item.posterUrl;
      if (url == null || url.isEmpty) continue;
      // Best-effort: a slow/failed fetch here just means that one tile
      // falls back to the normal fade-in-on-build behavior later, same
      // as before this existed — never worth surfacing as an error.
      precacheImage(NetworkImage(url), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissHint() {
    if (_showBrowseHint) setState(() => _showBrowseHint = false);
  }

  List<MediaItem> _buildReel() {
    final shuffled = [...widget.pool]..shuffle(_rnd);
    final reel = <MediaItem>[];
    while (reel.length < 44) {
      shuffled.shuffle(_rnd);
      reel.addAll(shuffled);
    }
    return reel;
  }

  /// A short, looping strip for a ghost column — doesn't need to cover the
  /// whole spin distance since the widget wraps it with a modulo, just
  /// enough variety that the loop isn't obviously repeating.
  List<MediaItem> _buildGhostStrip() {
    if (widget.pool.isEmpty) return const [];
    final shuffled = [...widget.pool]..shuffle(_rnd);
    final strip = <MediaItem>[];
    while (strip.length < 14) {
      shuffled.shuffle(_rnd);
      strip.addAll(shuffled);
    }
    return strip;
  }

  void _spin() {
    if (_phase == _Phase.spinning) return;
    final reel = _buildReel();
    final targetIndex = reel.length - 6 - _rnd.nextInt(6);
    setState(() {
      _phase = _Phase.spinning;
      _reel = reel;
      _ghostLeft = _buildGhostStrip();
      _ghostRight = _buildGhostStrip();
      _result = null;
      _resultIndex = null;
      _addedToPlan = false;
      _showBrowseHint = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSpin(targetIndex));
  }

  Future<void> _runSpin(int targetIndex) async {
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(0);
    // The ListView's top/bottom padding is (viewport/2 - itemHeight/2), so a
    // tile's own center sits at `padding + i*extent + gap/2 + itemHeight/2`
    // in content coordinates. Solving for the scroll offset that puts that
    // center in the middle of the viewport cancels the padding term out
    // entirely — the previous formula still subtracted it, which is what
    // left the landed tile straddling the pointer frame instead of sitting
    // inside it.
    final target = targetIndex * _extent + _itemGap / 2;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
    await _controller.animateTo(
      clamped,
      duration: const Duration(milliseconds: 2600),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      _phase = _Phase.landed;
      _result = _reel[targetIndex];
      _resultIndex = targetIndex;
      _showBrowseHint = true;
    });
    // Doesn't overstay: fades on its own if the person doesn't touch the
    // reel, same as it would if they'd already noticed and moved on.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _phase == _Phase.landed) _dismissHint();
    });
  }

  /// Picking any other poster in the reel, not just the one it landed on.
  /// Re-centers the tapped tile under the pointer frame so the frame keeps
  /// meaning what it looks like it means — "this one" — rather than staying
  /// stuck wherever the spin happened to stop.
  Future<void> _selectItem(int index) async {
    if (_phase != _Phase.landed || !_controller.hasClients) return;
    _dismissHint();
    setState(() {
      _result = _reel[index];
      _resultIndex = index;
      _addedToPlan = false;
    });
    final target = index * _extent + _itemGap / 2;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
    await _controller.animateTo(
      clamped,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _addToPlan() async {
    final result = _result;
    if (result == null || _addingToPlan || _addedToPlan) return;
    setState(() => _addingToPlan = true);
    if (widget.onSecondary != null) {
      final winner = await widget.onSecondary!(context, result);
      if (!mounted) return;
      if (winner != null) {
        Navigator.of(context).pop(winner);
        return;
      }
      setState(() => _addingToPlan = false);
      return;
    }
    try {
      await context.read<AppState>().feed.react(result, 'like');
      if (!mounted) return;
      setState(() {
        _addingToPlan = false;
        _addedToPlan = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingToPlan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('couldn\'t add that just now — try again'.tr)),
      );
    }
  }

  void _open() {
    final result = _result;
    if (result == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: result.id,
          source: result.source,
          mediaType: result.mediaType,
          seedTitle: result.title.display,
          seedPosterUrl: result.posterUrl,
        ),
      ),
    );
  }

  IconData _typeIcon(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return Icons.local_movies_outlined;
      case 'series':
        return Icons.live_tv_outlined;
      case 'anime':
        return Icons.auto_awesome_outlined;
      case 'manga':
        return Icons.import_contacts_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'game':
        return Icons.sports_esports_outlined;
      default:
        return Icons.casino_outlined;
    }
  }

  Widget _reelTile(MediaItem item, {required bool dim, required bool selected, VoidCallback? onTap}) {
    final color = SeenlyPalette.mediaColor(item.mediaType);
    final placeholder = Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(_typeIcon(item.mediaType), size: 56, color: SeenlyPalette.paper.withOpacity(0.7)),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dim ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _itemWidth,
          height: _itemHeight,
          margin: const EdgeInsets.symmetric(vertical: _itemGap / 2),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
              width: selected ? 3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (selected ? SeenlyPalette.accent : SeenlyPalette.ink).withOpacity(selected ? 0.22 : 0.10),
                blurRadius: selected ? 22 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: item.posterUrl != null && item.posterUrl!.isNotEmpty
              ? FadeInNetworkImage(url: item.posterUrl!, placeholder: placeholder)
              : placeholder,
        ),
      ),
    );
  }

  /// One flanking column: small, dimmed, softly blurred posters that
  /// loop endlessly and drift in parallax with the real reel. `factor`
  /// < 1 keeps them lagging behind the center column so the whole thing
  /// reads as depth rather than three identical reels.
  Widget _ghostColumn(List<MediaItem> strip, {required double factor, required double width}) {
    if (strip.isEmpty || width < 36) return const SizedBox.shrink();
    final tileWidth = width;
    final tileHeight = tileWidth * _ghostRatio;
    final loopExtent = tileHeight + _ghostGap;
    final loopHeight = loopExtent * strip.length;
    return ClipRect(
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.18, 0.82, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SizedBox(
          height: _viewportHeight,
          child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final raw = _controller.hasClients ? _controller.offset * factor : 0.0;
            final shift = raw % loopHeight;
            return OverflowBox(
              minHeight: 0,
              maxHeight: loopHeight * 2,
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, -shift),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // Two laps back-to-back so the loop point is never on screen.
                  children: [...strip, ...strip].map((item) {
                    final color = SeenlyPalette.mediaColor(item.mediaType);
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: _ghostGap / 2),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
                        child: Opacity(
                          opacity: 0.38,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.matrix(<double>[
                              0.28, 0.5, 0.1, 0, 0,
                              0.28, 0.5, 0.1, 0, 0,
                              0.28, 0.5, 0.1, 0, 0,
                              0, 0, 0, 1, 0,
                            ]),
                            child: Container(
                              width: tileWidth,
                              height: tileHeight,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: item.posterUrl != null && item.posterUrl!.isNotEmpty
                                  ? Image.network(item.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                                  : Icon(_typeIcon(item.mediaType), color: SeenlyPalette.paper.withOpacity(0.6)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('spin the reel'.tr, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportHeight = constraints.maxHeight;
                  // Center column sized off real poster proportions (2:3),
                  // capped so on wide screens it doesn't balloon. Whatever's
                  // left on each side goes to the ghost columns instead of
                  // sitting there as bare background.
                  _itemWidth = (constraints.maxWidth * 0.5).clamp(150.0, 220.0);
                  final sideWidth = ((constraints.maxWidth - _itemWidth - 24) / 2).clamp(0.0, 130.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (sideWidth >= 36) ...[
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: sideWidth,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _ghostColumn(_ghostLeft, factor: _leftFactor, width: sideWidth * 0.82),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: sideWidth,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _ghostColumn(_ghostRight, factor: _rightFactor, width: sideWidth * 0.82),
                          ),
                        ),
                      ],
                      _reel.isEmpty
                          ? Center(
                              child: Text(
                                'tap spin to start'.tr,
                                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.placeholder),
                              ),
                            )
                          : ShaderMask(
                              shaderCallback: (rect) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                                stops: [0.0, 0.14, 0.86, 1.0],
                              ).createShader(rect),
                              blendMode: BlendMode.dstIn,
                              child: NotificationListener<ScrollStartNotification>(
                                onNotification: (n) {
                                  if (n.dragDetails != null) _dismissHint();
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _controller,
                                  scrollDirection: Axis.vertical,
                                  physics: _phase == _Phase.landed
                                      ? const BouncingScrollPhysics()
                                      : const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.symmetric(vertical: _viewportHeight / 2 - _itemHeight / 2),
                                  itemCount: _reel.length,
                                  itemBuilder: (context, index) => Center(
                                    child: _reelTile(
                                      _reel[index],
                                      dim: _phase == _Phase.spinning,
                                      selected: _phase == _Phase.landed && index == _resultIndex,
                                      onTap: _phase == _Phase.landed ? () => _selectItem(index) : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      IgnorePointer(
                        child: Container(
                          width: _itemWidth + 18,
                          height: _itemHeight + 18,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: SeenlyPalette.accent, width: 3),
                            boxShadow: [
                              BoxShadow(color: SeenlyPalette.accent.withOpacity(0.22), blurRadius: 26),
                            ],
                          ),
                        ),
                      ),
                      if (_phase == _Phase.landed)
                        Positioned(
                          bottom: 10,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 320),
                              opacity: _showBrowseHint ? 1 : 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: SeenlyPalette.ink.withOpacity(0.82),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.swap_vert_rounded, size: 16, color: SeenlyPalette.paper.withOpacity(0.9)),
                                    const SizedBox(width: 7),
                                    Text(
                                      'листай и выбери любой постер'.tr,
                                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.paper.withOpacity(0.92), weight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                height: 46,
                child: _phase == _Phase.landed && result != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            result.title.display,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(size: 17, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [result.mediaType, if (result.year != null) '${result.year}'].join(' · '),
                            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
                          ),
                        ],
                      )
                    : Center(
                        child: Text(
                          _phase == _Phase.spinning ? 'rolling…' : 'ready when you are',
                          style: SeenlyText.serif(italic: true, size: 13.5, color: SeenlyPalette.inkMuted),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
              child: Column(
                children: [
                  if (_phase == _Phase.landed) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _SecondaryButton(
                            icon: Icons.rotate_right_rounded,
                            label: 'spin again',
                            onTap: _spin,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SecondaryButton(
                            icon: _addedToPlan ? widget.secondaryDoneIcon : widget.secondaryIcon,
                            label: _addedToPlan ? widget.secondaryDoneLabel : widget.secondaryLabel,
                            onTap: _addedToPlan ? null : _addToPlan,
                            loading: _addingToPlan,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(label: 'open', onTap: _open),
                  ] else
                    PrimaryButton(
                      label: _phase == _Phase.spinning ? 'rolling…' : 'spin',
                      loading: _phase == _Phase.spinning,
                      onTap: _phase == _Phase.spinning ? null : _spin,
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

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _SecondaryButton({required this.icon, required this.label, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.96,
      child: Opacity(
        opacity: onTap == null && !loading ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.border),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.ink),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 17, color: SeenlyPalette.ink),
                    const SizedBox(width: 7),
                    Text(label, style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.ink, weight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}
