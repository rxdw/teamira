import 'package:flutter/material.dart';

import 'wow_motion.dart';

/// A poster image that drifts inside its own frame as the page scrolls —
/// the same trick a parallax hero image uses, just applied per-tile: the
/// image is rendered taller than the tile and shifted up/down based on
/// how far the tile has traveled from the middle of the screen, so tiles
/// above center nudge one way and tiles below nudge the other, and the
/// crossover happens right as a tile passes through the middle of the
/// viewport. The frame itself (and everything drawn on top of the image —
/// title, gradient) never moves; only the image inside drifts, clipped to
/// the frame at all times.
///
/// Purely a `FadeInNetworkImage` replacement visually — same [url]/[fit]/
/// [placeholder] contract — so existing call sites swap in without
/// touching layout. [tileHeight] must match the frame's actual height
/// (the fixed height the surrounding `Container`/`SizedBox` gives this
/// tile) since that's what the oversized image is measured against.
class ParallaxPoster extends StatefulWidget {
  final String? url;
  final Widget placeholder;
  final double tileHeight;
  final BoxFit fit;

  /// Max pixels the image drifts from its resting position at either
  /// extreme of the screen. Kept small — this is meant to read as
  /// "alive", not as a slide.
  final double strength;

  const ParallaxPoster({
    super.key,
    required this.url,
    required this.placeholder,
    required this.tileHeight,
    this.fit = BoxFit.cover,
    this.strength = 14,
  });

  @override
  State<ParallaxPoster> createState() => _ParallaxPosterState();
}

class _ParallaxPosterState extends State<ParallaxPoster> {
  final GlobalKey _frameKey = GlobalKey();
  ScrollPosition? _scrollPosition;
  double _shift = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Whatever Scrollable this tile happens to be inside of right now —
    // Home's outer CustomScrollView today, but this widget doesn't need
    // to know or care which one.
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _scrollPosition)) {
      _scrollPosition?.removeListener(_handleScroll);
      _scrollPosition = position;
      _scrollPosition?.addListener(_handleScroll);
      // First layout hasn't happened yet on the very first call, so the
      // initial position (a tile that starts on-screen, e.g. right at
      // the top on first load) is picked up a frame later rather than
      // left at its default rest position.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
    }
  }

  void _handleScroll() {
    if (!mounted) return;
    final box = _frameKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight <= 0) return;
    final tileTop = box.localToGlobal(Offset.zero).dy;
    final tileCenter = tileTop + box.size.height / 2;
    final screenCenter = screenHeight / 2;
    // -1 (tile centered at the very top) .. +1 (tile centered at the
    // very bottom), 0 right at the middle of the screen.
    final normalized = ((tileCenter - screenCenter) / screenCenter).clamp(-1.0, 1.0);
    final next = normalized * widget.strength;
    if ((next - _shift).abs() > 0.1) {
      setState(() => _shift = next);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_handleScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overscan = widget.tileHeight + widget.strength * 2;
    return ClipRect(
      key: _frameKey,
      child: SizedBox(
        height: widget.tileHeight,
        child: OverflowBox(
          minHeight: overscan,
          maxHeight: overscan,
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(0, _shift),
            child: widget.url != null
                ? FadeInNetworkImage(
                    url: widget.url!,
                    fit: widget.fit,
                    placeholder: widget.placeholder,
                  )
                : widget.placeholder,
          ),
        ),
      ),
    );
  }
}
