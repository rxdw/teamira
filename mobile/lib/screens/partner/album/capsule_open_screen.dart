import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../utils/album_dates.dart';
import '../../../widgets/themed_loading_indicator.dart';
import '../../../widgets/wow_motion.dart';
import 'album_strings.dart';
import 'album_widgets.dart';

/// The capsule ceremony. Tells the server this person is opening it (which
/// also returns the letters — sealed text is never sent before this, and
/// the server refuses before the date by its own clock), then plays: a
/// night sky, an envelope that opens on a tap, the letters unfolding one
/// after another, a little confetti.
///
/// Someone who has already seen it open skips the envelope and lands on
/// the letters — reopening a capsule is reading, not a second ceremony.
Future<void> showCapsuleOpening(
  BuildContext context, {
  required Capsule capsule,
  required String partnerName,
  required DateTime serverToday,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => _CapsuleOpenScreen(
        capsule: capsule,
        partnerName: partnerName,
        serverToday: serverToday,
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

const Color _nightTop = Color(0xFF1B1430);
const Color _nightBottom = Color(0xFF3A2456);

class _CapsuleOpenScreen extends StatefulWidget {
  final Capsule capsule;
  final String partnerName;
  final DateTime serverToday;
  const _CapsuleOpenScreen({
    required this.capsule,
    required this.partnerName,
    required this.serverToday,
  });

  @override
  State<_CapsuleOpenScreen> createState() => _CapsuleOpenScreenState();
}

class _CapsuleOpenScreenState extends State<_CapsuleOpenScreen> with SingleTickerProviderStateMixin {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  Capsule? _loaded;
  String? _error;
  bool _opened = false; // the envelope has been tapped (or skipped)
  bool _confetti = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final capsule = await _service.openCapsule(widget.capsule.id);
      if (!mounted) return;
      setState(() => _loaded = capsule);
      if (widget.capsule.openedByMe) {
        // Seen before: straight to the letters.
        _opened = true;
        _open.value = 1;
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e));
    }
  }

  Future<void> _tapEnvelope() async {
    if (_opened || _loaded == null) return;
    HapticFeedback.heavyImpact();
    setState(() => _opened = true);
    if (albumReduceMotion(context)) {
      _open.value = 1;
      return;
    }
    await _open.forward();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _confetti = true);
  }

  /// "год назад" / "5 месяцев назад" / "12 дней назад".
  String _ago(int days) {
    if (days < 1) return at('сегодня', 'today');
    if (days < 60) return at('${daysLabel(days)} назад', '${daysLabel(days)} ago');
    final months = (days / 30.4).round();
    if (months < 24) return at('${monthsLabel(months)} назад', '${monthsLabel(months)} ago');
    final years = (days / 365.25).round();
    return at('${yearsLabel(years)} назад', '${yearsLabel(years)} ago');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nightTop,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_nightTop, _nightBottom],
                ),
              ),
            ),
          ),
          Positioned.fill(child: AlbumSparks(color: SeenlyPalette.mustard, count: 20, opacity: 0.7)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body(context)),
              ],
            ),
          ),
          if (_confetti) const Positioned.fill(child: AlbumConfetti()),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 16, color: Colors.white70),
              ),
              const SizedBox(height: 18),
              ClayButton(label: at('повторить', 'retry'), expand: false, onTap: _fetch),
            ],
          ),
        ),
      );
    }
    final capsule = _loaded;
    if (capsule == null) {
      return const Center(child: ThemedLoadingIndicator());
    }
    final ru = LocaleService.appIsRussian;
    final createdDay = DateTime(
      capsule.createdAt.toLocal().year,
      capsule.createdAt.toLocal().month,
      capsule.createdAt.toLocal().day,
    );
    final ago = _ago(albumDaysBetween(createdDay, widget.serverToday));
    final title = (capsule.title != null && capsule.title!.trim().isNotEmpty)
        ? capsule.title!
        : at('капсула времени', 'time capsule');

    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final finished = _opened && _open.value >= 0.999;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              Entrance(
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(size: 24, weight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      at(
                        'запечатана $ago · ${albumDateLabel(capsule.opensOn, ru: ru)}',
                        'sealed $ago · ${albumDateLabel(capsule.opensOn, ru: ru)}',
                      ),
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 12.5, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (!finished)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tapEnvelope,
                  child: Column(
                    children: [
                      BreathingGlow(
                        color: SeenlyPalette.mustard,
                        size: 340,
                        maxOpacity: _opened ? 0.0 : 0.3,
                        child: EnvelopeView(
                          progress: _open.value,
                          width: 268,
                          color: const Color(0xFFF3E7CF),
                          sealColor: SeenlyPalette.accent,
                          letter: Container(
                            decoration: BoxDecoration(
                              color: SeenlyPalette.paper,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _opened ? 0 : 1,
                        child: Text(
                          at('нажмите, чтобы открыть', 'tap to open'),
                          style: SeenlyText.handwrittenNote(size: 19, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._letters(capsule),
              if (finished) ...[
                const SizedBox(height: 26),
                Entrance(
                  delay: Duration(milliseconds: 500 + 380 * capsule.letters.length),
                  child: ClayButton(
                    label: at('в книгу', 'to the book'),
                    icon: Icons.menu_book_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _letters(Capsule capsule) {
    final ru = LocaleService.appIsRussian;
    final letters = capsule.letters;
    final widgets = <Widget>[];
    for (var i = 0; i < letters.length; i++) {
      final l = letters[i];
      final sealedDay = l.sealedAt.toLocal();
      final name = l.isMine ? at('вы', 'you') : widget.partnerName;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Entrance(
            key: ValueKey('letter-$i'),
            delay: Duration(milliseconds: 250 + 380 * i),
            duration: const Duration(milliseconds: 700),
            riseBy: 40,
            child: NotePaper(
              body: l.body,
              byline: at(
                'письмо от $name · ${albumDateLabel(sealedDay, ru: ru)}',
                'letter from $name · ${albumDateLabel(sealedDay, ru: ru)}',
              ),
              tint: l.isMine ? SeenlyPalette.periwinkle : SeenlyPalette.mustard,
              tilt: i.isEven ? -0.012 : 0.012,
              fontSize: 19,
            ),
          ),
        ),
      );
    }
    if (letters.length < 2) {
      widgets.add(
        Entrance(
          delay: Duration(milliseconds: 250 + 380 * letters.length),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              at(
                'письмо от ${widget.partnerName} так и не появилось — но капсула всё равно ваша',
                '${widget.partnerName} never added a letter — but the capsule is still yours',
              ),
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: Colors.white60),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
