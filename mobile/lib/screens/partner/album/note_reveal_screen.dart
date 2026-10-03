import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/wow_motion.dart';
import 'album_strings.dart';
import 'album_widgets.dart';

/// Plays the moment a sealed note becomes readable: the evening has been
/// marked watched, an envelope is waiting, the person taps it, it opens.
///
/// Used twice — straight after "mark watched" on the co-viewing screen
/// (the partner's note has just unsealed), and from the book when a page is
/// still unread (the partner marked the evening, this person is opening it
/// later). The "opened" flag is stored server-side per reader, so the
/// ceremony plays exactly once per person even across devices; reopening a
/// page later just shows the note.
Future<void> showPageReveal(
  BuildContext context, {
  required AlbumPage page,
  required String partnerName,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => _RevealScreen(page: page, partnerName: partnerName),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class _RevealScreen extends StatefulWidget {
  final AlbumPage page;
  final String partnerName;
  const _RevealScreen({required this.page, required this.partnerName});

  @override
  State<_RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends State<_RevealScreen> with SingleTickerProviderStateMixin {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool _opened = false;
  bool _showConfetti = false;
  String? _reaction;

  /// Read fresh on every frame (the ceremony is driven by [_open]), never
  /// captured once at the top of build.
  bool get _finished => _opened && _open.value >= 0.999;

  AlbumNote? get _theirs => widget.page.partner;
  AlbumNote? get _mine => widget.page.mine;

  @override
  void initState() {
    super.initState();
    _reaction = _theirs?.reaction;
    // Already seen before (or nothing to unseal): skip the ceremony and
    // land on the finished state.
    if (_theirs == null || _theirs!.opened) {
      _opened = true;
      _open.value = 1;
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> _openIt() async {
    if (_opened) return;
    HapticFeedback.mediumImpact();
    setState(() => _opened = true);
    final theirs = _theirs;
    if (theirs != null) {
      // Fire and forget: the ceremony shouldn't wait on the network, and a
      // miss only means it may play once more next time.
      _service.markNoteOpened(theirs.id).catchError((_) {});
    }
    if (albumReduceMotion(context)) {
      _open.value = 1;
      setState(() => _showConfetti = false);
      return;
    }
    await _open.forward();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _showConfetti = true);
  }

  Future<void> _react(String? emoji) async {
    final theirs = _theirs;
    if (theirs == null) return;
    final previous = _reaction;
    setState(() => _reaction = emoji);
    try {
      await _service.react(theirs.id, emoji);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reaction = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final title = widget.page.title(ru: ru);
    final theirs = _theirs;
    final mine = _mine;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(SeenlyPalette.background, SeenlyPalette.pink, 0.16)!,
                    SeenlyPalette.background,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: AlbumSparks(color: SeenlyPalette.coral, count: 14)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: SeenlyPalette.ink),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _open,
                    builder: (context, _) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      child: Column(
                        children: [
                          Entrance(
                            child: Column(
                              children: [
                                Text(
                                  theirs != null
                                      ? at('записка от ${widget.partnerName}', 'a note from ${widget.partnerName}')
                                      : at('ваша записка в книге', 'your note is in the book'),
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.serif(size: 22, weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          if (theirs != null) _stage(context, theirs, _finished),
                          if (theirs == null && mine != null)
                            Entrance(
                              delay: const Duration(milliseconds: 150),
                              child: Column(
                                children: [
                                  NotePaper(
                                    body: mine.body,
                                    mood: mine.mood,
                                    byline: albumByline(mine: true, name: widget.partnerName),
                                    reaction: mine.reaction,
                                    tilt: -0.015,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    at(
                                      '${widget.partnerName} в этот раз ничего не оставил(а) — '
                                          'но ваша записка теперь навсегда в книге',
                                      '${widget.partnerName} didn\'t leave one this time — '
                                          'but yours now lives in the book',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                          if (_finished && theirs != null) ...[
                            const SizedBox(height: 22),
                            Entrance(
                              delay: const Duration(milliseconds: 250),
                              riseBy: 12,
                              child: Column(
                                children: [
                                  Text(
                                    at('ответить', 'reply'),
                                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: EmojiChoiceRow(
                                      options: kAlbumReactions,
                                      selected: _reaction,
                                      onChanged: _react,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (mine != null) ...[
                              const SizedBox(height: 30),
                              Entrance(
                                delay: const Duration(milliseconds: 450),
                                riseBy: 12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      at('а вот что оставили вы', 'and what you left'),
                                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                                    ),
                                    const SizedBox(height: 12),
                                    NotePaper(
                                      body: mine.body,
                                      mood: mine.mood,
                                      tint: SeenlyPalette.periwinkle,
                                      tilt: 0.012,
                                      fontSize: 16,
                                      reaction: mine.reaction,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                          if (_finished || theirs == null) ...[
                            const SizedBox(height: 28),
                            Entrance(
                              delay: const Duration(milliseconds: 600),
                              child: ClayButton(
                                label: at('в книгу', 'to the book'),
                                icon: Icons.menu_book_rounded,
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showConfetti) const Positioned.fill(child: AlbumConfetti()),
        ],
      ),
    );
  }

  /// The envelope while it's closed and opening, the note once it's out.
  Widget _stage(BuildContext context, AlbumNote theirs, bool finished) {
    final p = _open.value;
    return Column(
      children: [
        if (!finished)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openIt,
            child: Column(
              children: [
                BreathingGlow(
                  color: SeenlyPalette.coral,
                  size: 320,
                  maxOpacity: _opened ? 0.0 : 0.22,
                  child: EnvelopeView(
                    progress: p,
                    width: 264,
                    letter: Container(
                      decoration: BoxDecoration(
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: CustomPaint(painter: _BlankLinesPainter(SeenlyPalette.mustard.withOpacity(0.3))),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _opened ? 0 : 1,
                  child: Text(
                    at('нажмите, чтобы открыть', 'tap to open'),
                    style: SeenlyText.handwrittenNote(size: 18, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ],
            ),
          )
        else
          Entrance(
            duration: const Duration(milliseconds: 620),
            riseBy: 34,
            child: NotePaper(
              body: theirs.body,
              mood: theirs.mood,
              byline: albumByline(mine: false, name: widget.partnerName),
              reaction: _reaction,
              tilt: -0.012,
              fontSize: 21,
            ),
          ),
      ],
    );
  }
}

class _BlankLinesPainter extends CustomPainter {
  final Color color;
  _BlankLinesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    var y = 16.0;
    var i = 0;
    while (y < size.height - 8) {
      final w = size.width * (i.isEven ? 0.78 : 0.56);
      canvas.drawLine(Offset(14, y), Offset(14 + w, y), paint);
      y += 15;
      i++;
    }
  }

  @override
  bool shouldRepaint(_BlankLinesPainter old) => old.color != color;
}
