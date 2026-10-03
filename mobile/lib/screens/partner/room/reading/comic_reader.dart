import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/user_avatar.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_strings.dart';
import 'comic_source.dart';
import 'reader_handle.dart';
import 'reading_locator.dart';
import 'reading_overlay.dart';

/// Draws a person's own comic archive, one page at a time. Swipe or tap the
/// edges to turn, pinch or double-tap to zoom, long-press to react or leave a
/// note on the page. Manga reads right to left by default (a switch at the top
/// flips it); the page order itself is the archive's, sorted naturally, so
/// "page 42" is the same page on every phone holding the same file.
class ComicReader extends StatefulWidget {
  final ComicArchive archive;
  final ReadLocator start;
  final bool rtl;
  final ValueChanged<bool> onRtlChanged;
  final ReaderHandle handle;
  final ReadingOverlayNotifier overlay;
  final ReaderMoved onMoved;
  final void Function(ReadLocator at, double fraction) onPin;

  /// Shown on the last page (circle members only).
  final VoidCallback? onFinish;

  /// Zen: pages dim and settle softly as they slide past instead of just sliding.
  final bool zen;
  const ComicReader({
    super.key,
    required this.archive,
    required this.start,
    required this.rtl,
    required this.onRtlChanged,
    required this.handle,
    required this.overlay,
    required this.onMoved,
    required this.onPin,
    this.onFinish,
    this.zen = false,
  });

  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader> {
  late final PageController _pages;
  final _zoom = TransformationController();
  final Map<int, Future<Uint8List>> _loading = {};
  Timer? _debounce;
  Timer? _programmaticTimer;
  bool _programmatic = false;
  bool _zoomed = false;
  late int _page;

  int get _count => widget.archive.pageCount;

  @override
  void initState() {
    super.initState();
    _page = widget.start.major.clamp(0, _count - 1);
    _pages = PageController(initialPage: _page);
    _zoom.addListener(_onZoom);
    widget.handle.attach(go: _goTo);
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit(byUser: false));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _programmaticTimer?.cancel();
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    _pages.dispose();
    widget.handle.detach();
    super.dispose();
  }

  void _onZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  double get _fraction => _count <= 1 ? 1.0 : _page / (_count - 1);

  void _emit({required bool byUser}) {
    if (!mounted) return;
    widget.onMoved(ReadLocator(ReadKind.cbz, _page), _fraction, byUser: byUser);
  }

  void _markProgrammatic() {
    _programmatic = true;
    _programmaticTimer?.cancel();
    _programmaticTimer = Timer(const Duration(milliseconds: 900), () => _programmatic = false);
  }

  void _goTo(ReadLocator at) {
    if (!mounted) return;
    final target = at.major.clamp(0, _count - 1);
    if (target == _page) return;
    _markProgrammatic();
    _zoom.value = Matrix4.identity();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || (target - _page).abs() > 1) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  void _onPageChanged(int i) {
    _page = i;
    _zoom.value = Matrix4.identity();
    final byUser = !_programmatic;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _emit(byUser: byUser));
    // Get the next page ready before it's asked for.
    for (final n in [i + 1, i - 1]) {
      if (n >= 0 && n < _count) _future(n);
    }
    setState(() {});
  }

  /// Visual left/right edge taps → forward or back in reading order.
  void _tapEdge({required bool right}) {
    final forward = widget.rtl ? !right : right;
    final next = (_page + (forward ? 1 : -1)).clamp(0, _count - 1);
    if (next == _page) return;
    HapticFeedback.selectionClick();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(next, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
  }

  Future<Uint8List> _future(int i) => _loading.putIfAbsent(i, () {
        // Off the current frame, so a big page never freezes a swipe.
        final f = Future<Uint8List>(() => widget.archive.page(i));
        if (_loading.length > 14) {
          final far = _loading.keys.where((k) => (k - _page).abs() > 4).toList();
          for (final k in far) {
            _loading.remove(k);
          }
        }
        return f;
      });

  /// In zen a page dims and shrinks a touch as it leaves, and comes back as it
  /// arrives, following the swipe itself (so it's never a separate animation to
  /// wait for). Outside zen the page is left exactly as it is.
  Widget _soft(int index, Widget page) {
    if (!widget.zen || (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) return page;
    return AnimatedBuilder(
      animation: _pages,
      child: page,
      builder: (context, child) {
        var away = 0.0;
        if (_pages.hasClients && _pages.position.haveDimensions) {
          away = ((_pages.page ?? _page.toDouble()) - index).abs().clamp(0.0, 1.0);
        }
        return Opacity(
          opacity: 1 - 0.55 * away,
          child: Transform.scale(scale: 1 - 0.06 * away, child: child),
        );
      },
    );
  }

  void _doubleTapZoom(Size size) {
    if (_zoom.value.getMaxScaleOnAxis() > 1.02) {
      _zoom.value = Matrix4.identity();
    } else {
      // Zoom about the middle of the page: scale s, then shift back by half of
      // what the scaling added on each side (column-major 4x4).
      const s = 2.3;
      final tx = -(s - 1) * size.width / 2;
      final ty = -(s - 1) * size.height / 2;
      _zoom.value = Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cacheWidth = (mq.size.width * mq.devicePixelRatio).round();
    return Stack(
      children: [
        PageView.builder(
          controller: _pages,
          reverse: widget.rtl,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: _count,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, i) => _soft(i, LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => _doubleTapZoom(Size(box.maxWidth, box.maxHeight)),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                widget.onPin(ReadLocator(ReadKind.cbz, i), _count <= 1 ? 1.0 : i / (_count - 1));
              },
              onTapUp: (d) {
                if (_zoomed) return;
                final x = d.localPosition.dx / box.maxWidth;
                if (x < 0.28) _tapEdge(right: false);
                if (x > 0.72) _tapEdge(right: true);
              },
              child: InteractiveViewer(
                transformationController: i == _page ? _zoom : null,
                minScale: 1,
                maxScale: 4,
                child: SizedBox(
                  width: box.maxWidth,
                  height: box.maxHeight,
                  child: FutureBuilder<Uint8List>(
                    future: _future(i),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return Center(
                          child: snap.hasError
                              ? Icon(Icons.broken_image_outlined, color: SeenlyPalette.inkFaint)
                              : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      return Image.memory(
                        snap.data!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        cacheWidth: cacheWidth,
                        errorBuilder: (_, __, ___) =>
                            Center(child: Icon(Icons.broken_image_outlined, color: SeenlyPalette.inkFaint)),
                      );
                    },
                  ),
                ),
              ),
            ),
          )),
        ),
        // Page number and reading direction.
        Positioned(
          left: 12,
          right: 12,
          top: 8,
          child: Row(children: [
            _chip(at('стр. ${_page + 1} из $_count', 'page ${_page + 1} of $_count')),
            const Spacer(),
            GestureDetector(
              onTap: () => widget.onRtlChanged(!widget.rtl),
              child: _chip(
                widget.rtl ? at('справа налево', 'right to left') : at('слева направо', 'left to right'),
                icon: Icons.swap_horiz_rounded,
              ),
            ),
          ]),
        ),
        // Who else is on this page, and the notes left on it.
        Positioned(
          right: 12,
          top: 46,
          child: ValueListenableBuilder<ReadingOverlay>(
            valueListenable: widget.overlay,
            builder: (context, o, _) {
              final here = ReadLocator(ReadKind.cbz, _page);
              final others = o.othersFor(here);
              final notes = o.notesFor(here);
              if (others.isEmpty && notes.isEmpty) return const SizedBox.shrink();
              return Row(mainAxisSize: MainAxisSize.min, children: [
                for (final p in others)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: SeenlyPalette.accent.withOpacity(0.55), width: 1.5),
                      ),
                      child: UserAvatar(
                        avatarUrl: p.avatarUrl,
                        avatarPreset: p.avatarPreset,
                        fallbackLetter: p.letter,
                        size: 22,
                      ),
                    ),
                  ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () => widget.onPin(here, _fraction),
                      child: _chip('${notes.length}', icon: Icons.edit_note_rounded, tint: SeenlyPalette.sage),
                    ),
                  ),
              ]);
            },
          ),
        ),
        if (widget.onFinish != null && _page == _count - 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: PressScale(
                haptics: true,
                onTap: widget.onFinish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: ClayBoxDecoration(color: SeenlyPalette.sage, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded, size: 18, color: SeenlyPalette.accentOnAccent),
                    const SizedBox(width: 6),
                    Text(at('дочитали', 'we’re done'),
                        style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(String text, {IconData? icon, Color? tint}) {
    final c = tint ?? SeenlyPalette.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 5)],
        Text(text, style: SeenlyText.serif(size: 12, italic: true, color: c)),
      ]),
    );
  }
}
