import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/user_avatar.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_strings.dart';
import 'book_source.dart';
import 'reader_handle.dart';
import 'reading_locator.dart';
import 'reading_overlay.dart';
import 'reading_strings.dart';

/// Draws a person's own EPUB: one chapter at a time, as a calm column of
/// text in the app's own reading style. A place is "chapter + paragraph",
/// which — because the book is read the same way on every device (see
/// book_source.dart) — is the same place on every phone holding the same file.
///
/// What the room adds on top: a small face beside the paragraph where someone
/// else is, a note mark where somebody wrote in the margin, and a long-press
/// on any paragraph to react or write a note pinned to it.
class EpubReader extends StatefulWidget {
  final LocalBook book;
  final ReadLocator start;
  final ReaderHandle handle;
  final ReadingOverlayNotifier overlay;
  final ReaderMoved onMoved;

  /// Long-press on a paragraph: where, how far through, which line.
  final void Function(ReadLocator at, double fraction, String quote) onPin;
  final int sizeIndex;
  final ValueChanged<int> onSizeChanged;

  /// Shown at the very end of the last chapter (circle members only).
  final VoidCallback? onFinish;

  /// The room is reading aloud: the paragraph being read glows for everyone
  /// and the reader's view scrolls it into place on every other phone.
  final bool aloud;

  /// I am the one reading aloud: I move the glowing line (tap a paragraph, or
  /// "next"), and nobody else does.
  final bool iAmReader;
  final void Function(ReadLocator at, double fraction)? onCursor;

  /// Zen: chapters change with a soft cross-fade and scrolling to a place glides.
  final bool zen;
  const EpubReader({
    super.key,
    required this.book,
    required this.start,
    required this.handle,
    required this.overlay,
    required this.onMoved,
    required this.onPin,
    required this.sizeIndex,
    required this.onSizeChanged,
    this.onFinish,
    this.aloud = false,
    this.iAmReader = false,
    this.onCursor,
    this.zen = false,
  });

  @override
  State<EpubReader> createState() => _EpubReaderState();
}

class _EpubReaderState extends State<EpubReader> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  Timer? _debounce;
  Timer? _programmaticTimer;
  bool _programmatic = false;

  late int _chapter;
  late int _initialIndex;
  int _top = 0;
  double _fade = 1;

  /// Where a place lands on the screen: at the top for reading on your own,
  /// a little lower when following a line read aloud so the lines before it
  /// are still in view.
  double get _alignment => widget.aloud ? 0.28 : 0.02;
  bool get _reduce => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  BookContent get _content => widget.book.content;
  List<BookBlock> get _blocks => _content.chapters[_chapter].blocks;

  @override
  void initState() {
    super.initState();
    final last = _content.chapters.length - 1;
    _chapter = widget.start.major.clamp(0, last);
    _initialIndex = widget.start.minor.clamp(0, _blocks.length - 1);
    _top = _initialIndex;
    widget.handle.attach(go: _goTo, quote: _quoteNow);
    _positions.itemPositions.addListener(_onPositions);
    // Tell the room where we start, so it can show it and begin the evening.
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit(byUser: false));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _programmaticTimer?.cancel();
    _positions.itemPositions.removeListener(_onPositions);
    widget.handle.detach();
    super.dispose();
  }

  ReadLocator get _here => ReadLocator(ReadKind.epub, _chapter, _top);

  void _emit({required bool byUser}) {
    if (!mounted) return;
    widget.onMoved(_here, _content.fractionAt(_chapter, _top), byUser: byUser);
  }

  String? _quoteNow() {
    final b = _blocks;
    for (var i = _top; i < b.length && i < _top + 6; i++) {
      if (!b[i].isBreak && b[i].text.isNotEmpty) return b[i].text;
    }
    return null;
  }

  void _markProgrammatic() {
    _programmatic = true;
    _programmaticTimer?.cancel();
    _programmaticTimer = Timer(const Duration(milliseconds: 1100), () => _programmatic = false);
  }

  void _onPositions() {
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty) return;
    final n = _blocks.length;
    var top = n;
    for (final p in pos) {
      if (p.itemTrailingEdge > 0.03 && p.index < top) top = p.index;
    }
    if (top >= n) top = n - 1;
    if (top < 0) top = 0;
    if (top == _top) return;
    _top = top;
    final byUser = !_programmatic;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _emit(byUser: byUser));
  }

  /// Moves to another chapter. In zen the old one fades out before the new one
  /// fades in, so a chapter never just snaps.
  Future<void> _swapChapter(int ch, int blk, {required bool byUser}) async {
    void apply() {
      setState(() {
        _chapter = ch;
        _initialIndex = blk;
        _top = blk;
        _fade = 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit(byUser: byUser));
    }

    if (!widget.zen || _reduce) {
      apply();
      return;
    }
    setState(() => _fade = 0);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) apply();
  }

  void _goTo(ReadLocator at) {
    if (!mounted) return;
    final ch = at.major.clamp(0, _content.chapters.length - 1);
    final blk = at.minor.clamp(0, _content.chapters[ch].blocks.length - 1);
    _markProgrammatic();
    if (ch != _chapter) {
      _swapChapter(ch, blk, byUser: false);
      return;
    }
    _top = blk;
    if (_scroll.isAttached) {
      if (_reduce) {
        _scroll.jumpTo(index: blk, alignment: _alignment);
      } else {
        _scroll.scrollTo(
          index: blk,
          alignment: _alignment,
          duration: Duration(milliseconds: widget.zen ? 800 : 480),
          curve: widget.zen ? Curves.easeInOutCubic : Curves.easeOutCubic,
        );
      }
    }
    _emit(byUser: false);
  }

  /// A person moving between chapters (the arrows, the "next chapter" card).
  void _turnChapter(int delta) {
    final next = (_chapter + delta).clamp(0, _content.chapters.length - 1);
    if (next == _chapter) return;
    HapticFeedback.selectionClick();
    _debounce?.cancel();
    _swapChapter(next, 0, byUser: true);
  }

  /// Reading aloud: the line moves to the next paragraph that has words in it
  /// (over to the next chapter at the end of this one) and the page follows.
  void _stepCursor() {
    final cb = widget.onCursor;
    if (cb == null) return;
    final cur = ReadLocator.tryParse(ReadKind.epub, widget.overlay.value.cursor) ?? _here;
    var ch = cur.major.clamp(0, _content.chapters.length - 1);
    var i = cur.minor + 1;
    while (true) {
      final blocks = _content.chapters[ch].blocks;
      while (i < blocks.length && blocks[i].isBreak) {
        i++;
      }
      if (i < blocks.length) break;
      if (ch >= _content.chapters.length - 1) return; // the end of the book
      ch++;
      i = 0;
    }
    final next = ReadLocator(ReadKind.epub, ch, i);
    HapticFeedback.selectionClick();
    cb(next, _content.fractionAt(ch, i));
    _goTo(next);
  }

  String _chapterTitle(int i) {
    final t = _content.chapters[i].title;
    return (t != null && t.isNotEmpty) ? t : at('глава ${i + 1}', 'chapter ${i + 1}');
  }

  @override
  Widget build(BuildContext context) {
    final size = readingTextSizes[widget.sizeIndex.clamp(0, readingTextSizes.length - 1)];
    final n = _blocks.length;
    final last = _chapter == _content.chapters.length - 1;
    final reader = widget.aloud && widget.iAmReader;
    return Column(
      children: [
        _header(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: (!widget.zen || _reduce) ? 1 : (_fade == 0 ? 200 : 420)),
                  curve: Curves.easeInOut,
                  opacity: _fade,
                  child: ScrollablePositionedList.builder(
                    key: ValueKey('chapter-$_chapter'),
                    itemCount: n + 1,
                    initialScrollIndex: _initialIndex,
                    initialAlignment: _alignment,
                    itemScrollController: _scroll,
                    itemPositionsListener: _positions,
                    itemBuilder: (context, i) {
                      if (i == n) return _endCard(last);
                      final at0 = ReadLocator(ReadKind.epub, _chapter, i);
                      final fraction = _content.fractionAt(_chapter, i);
                      return _BlockTile(
                        block: _blocks[i],
                        at: at0,
                        fontSize: size,
                        overlay: widget.overlay,
                        onPin: () => widget.onPin(at0, fraction, _blocks[i].text),
                        // The reader of an aloud room taps the line they're on.
                        onTap: (reader && widget.onCursor != null && !_blocks[i].isBreak)
                            ? () {
                                HapticFeedback.selectionClick();
                                widget.onCursor!(at0, fraction);
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ),
              if (reader)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: PressScale(
                    haptics: false,
                    scaleTo: 0.9,
                    onTap: _stepCursor,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: ClayBoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_downward_rounded, color: SeenlyPalette.accentOnAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final total = _content.chapters.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _chapter > 0 ? () => _turnChapter(-1) : null,
          icon: Icon(Icons.chevron_left_rounded, color: SeenlyPalette.inkMuted),
        ),
        Expanded(
          child: Column(children: [
            Text(_chapterTitle(_chapter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 14, weight: FontWeight.w600)),
            Text(at('глава ${_chapter + 1} из $total', 'chapter ${_chapter + 1} of $total'),
                style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkFaint)),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _chapter < total - 1 ? () => _turnChapter(1) : null,
          icon: Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkMuted),
        ),
        PopupMenuButton<int>(
          tooltip: at('размер текста', 'text size'),
          color: SeenlyPalette.paper,
          icon: Icon(Icons.text_fields_rounded, size: 20, color: SeenlyPalette.inkMuted),
          onSelected: widget.onSizeChanged,
          itemBuilder: (_) => [
            for (var i = 0; i < readingTextSizes.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Row(children: [
                  Icon(i == widget.sizeIndex ? Icons.check_rounded : Icons.circle_outlined,
                      size: 16, color: i == widget.sizeIndex ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
                  const SizedBox(width: 10),
                  Text('Аа', style: SeenlyText.serif(size: readingTextSizes[i])),
                ]),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _endCard(bool lastChapter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 60),
      child: Column(children: [
        Text('· · ·', style: SeenlyText.serif(size: 20, color: SeenlyPalette.inkFaint)),
        const SizedBox(height: 18),
        if (!lastChapter)
          PressScale(
            haptics: true,
            onTap: () => _turnChapter(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(20)),
              child: Text(
                at('дальше · ${_chapterTitle(_chapter + 1)}', 'next · ${_chapterTitle(_chapter + 1)}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 15, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent),
              ),
            ),
          )
        else ...[
          Text(at('вот и конец', 'the end'), style: SeenlyText.serif(size: 17, italic: true, color: SeenlyPalette.inkMuted)),
          if (widget.onFinish != null) ...[
            const SizedBox(height: 14),
            PressScale(
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
          ],
        ],
      ]),
    );
  }
}

/// One paragraph (or heading, quote, scene break) with whatever the room has
/// left on it. Listens to the overlay itself, so a partner turning a page
/// redraws the one paragraph with their face on it, not the chapter.
class _BlockTile extends StatelessWidget {
  final BookBlock block;
  final ReadLocator at;
  final double fontSize;
  final ReadingOverlayNotifier overlay;
  final VoidCallback onPin;

  /// Only set for the reader of an aloud room: tap = "this is the line".
  final VoidCallback? onTap;
  const _BlockTile({
    required this.block,
    required this.at,
    required this.fontSize,
    required this.overlay,
    required this.onPin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (block.isBreak) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text('· · ·', style: SeenlyText.serif(size: 18, color: SeenlyPalette.inkFaint))),
      );
    }
    return ValueListenableBuilder<ReadingOverlay>(
      valueListenable: overlay,
      builder: (context, o, _) {
        final notes = o.notesFor(at);
        final others = o.othersFor(at);
        final cursor = o.isCursor(at);
        final mine = o.iHighlighted(at);
        final theirs = o.othersHighlighted(at);
        // The line being read aloud outranks a highlight; a highlight is tinted
        // by whose it is (mine, theirs, or both).
        Color? tint;
        Color? bar;
        if (cursor) {
          tint = SeenlyPalette.accent.withOpacity(0.16);
          bar = SeenlyPalette.accent;
        } else if (mine || theirs) {
          tint = (mine && theirs)
              ? Color.alphaBlend(SeenlyPalette.sage.withOpacity(0.14), SeenlyPalette.accent.withOpacity(0.12))
              : mine
                  ? SeenlyPalette.accent.withOpacity(0.12)
                  : SeenlyPalette.sage.withOpacity(0.16);
          bar = mine ? SeenlyPalette.accent.withOpacity(0.55) : SeenlyPalette.sage.withOpacity(0.6);
        }
        final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onPin();
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, block.isHeading ? 18 : 3, 12, block.isHeading ? 8 : 3),
            child: AnimatedContainer(
              duration: Duration(milliseconds: reduce ? 1 : 340),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              decoration: BoxDecoration(
                color: tint ?? Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: bar ?? Colors.transparent, width: 3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _text(context),
              if (notes.isNotEmpty || others.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    for (final p in others)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: SeenlyPalette.accent.withOpacity(0.5), width: 1.5),
                          ),
                          child: UserAvatar(
                            avatarUrl: p.avatarUrl,
                            avatarPreset: p.avatarPreset,
                            fallbackLetter: p.letter,
                            size: 18,
                          ),
                        ),
                      ),
                    if (others.isNotEmpty)
                      Text(
                        others.map((p) => p.name.toLowerCase()).join(', '),
                        style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkFaint),
                      ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onPin,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.sage.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_note_rounded, size: 14, color: SeenlyPalette.sage),
                            const SizedBox(width: 4),
                            Text('${notes.length}', style: SeenlyText.serif(size: 11.5, color: SeenlyPalette.sage)),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                ),
            ]),
            ),
          ),
        );
      },
    );
  }

  Widget _text(BuildContext context) {
    if (block.isHeading) {
      final scale = switch (block.level) { 1 => 1.38, 2 => 1.22, _ => 1.1 };
      return Text(
        block.text,
        textAlign: TextAlign.center,
        style: SeenlyText.serif(size: fontSize * scale, weight: FontWeight.w700).copyWith(height: 1.3),
      );
    }
    final base = SeenlyText.serif(size: fontSize, color: SeenlyPalette.ink).copyWith(height: 1.62);
    if (block.quote) {
      return Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: SeenlyPalette.accent.withOpacity(0.4), width: 3))),
        child: Text(block.text, style: base.copyWith(fontStyle: FontStyle.italic, color: SeenlyPalette.inkMuted)),
      );
    }
    return Text('\u2003${block.text}', style: base);
  }
}
