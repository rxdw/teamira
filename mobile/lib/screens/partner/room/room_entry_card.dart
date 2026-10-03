import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/circle_review.dart';
import '../../../models/co_view_room.dart';
import '../../../services/api_client.dart';
import '../../../services/circle_review_service.dart';
import '../../../services/co_view_room_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'circle_review_screen.dart';
import 'room_launcher.dart';
import 'room_start_sheet.dart';
import 'room_strings.dart';

/// The biggest thing on the "вы и …" screen, on purpose: the room.
///
/// Three looks, one card:
///  * nobody is in a room — a calm invitation with a soft breathing screen
///    and a single "начать" button;
///  * someone is waiting or watching — their faces, what they're watching,
///    and a "войти" that pulses gently;
///  * you are the only one in it (you left and came back) — "вернуться".
///
/// Under it, only when there is something to do, sit the soft "оценим
/// вместе?" cards for evenings whose joint review is waiting on you.
class RoomHeroSection extends StatefulWidget {
  const RoomHeroSection({super.key});

  @override
  State<RoomHeroSection> createState() => _RoomHeroSectionState();
}

class _RoomHeroSectionState extends State<RoomHeroSection> with WidgetsBindingObserver {
  final _rooms = CoViewRoomService(ApiClient.instance);
  final _reviews = CircleReviewService(ApiClient.instance);
  RoomState? _room;
  List<CircleReview> _pending = const [];
  List<CircleReview> _ready = const []; // opened, but you haven't looked yet
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait<Object?>([_rooms.active(), _reviews.pending(), _reviews.list(limit: 6)]);
      final prefs = await SharedPreferences.getInstance();
      final recent = results[2] as List<CircleReview>;
      final ready = [
        for (final r in recent)
          if (r.revealed &&
              prefs.getBool('circle_review_opened_${r.id}') != true &&
              DateTime.now().difference(r.createdAt).inDays < 14)
            r,
      ].take(2).toList();
      if (!mounted) return;
      setState(() {
        _room = results[0] as RoomState?;
        _pending = results[1] as List<CircleReview>;
        _ready = ready;
        _loaded = true;
      });
    } catch (_) {
      if (mounted && !_loaded) setState(() => _loaded = true);
    }
  }

  Future<void> _enter() async {
    final r = _room;
    if (r == null) {
      await showRoomStartSheet(context);
    } else {
      await RoomLauncher.enter(context, r);
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(room: _room, onTap: _enter),
        for (final r in _ready)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ReadyReviewCard(
              review: r,
              onTap: () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => CircleReviewScreen(reviewId: r.id, title: r.title, posterUrl: r.posterUrl),
                ));
                if (mounted) _refresh();
              },
            ),
          ),
        for (final r in _pending)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _PendingReviewCard(
              review: r,
              onTap: () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => CircleReviewScreen(reviewId: r.id, title: r.title, posterUrl: r.posterUrl),
                ));
                if (mounted) _refresh();
              },
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final RoomState? room;
  final VoidCallback onTap;
  const _HeroCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = room;
    final here = r?.present.where((p) => !p.isYou).toList() ?? const <RoomParticipant>[];
    final iAmIn = r?.me?.present ?? false;
    final live = r != null;
    final accent = live ? SeenlyPalette.sage : SeenlyPalette.accent;

    final String headline;
    final String sub;
    final String button;
    final reading = r?.isReading ?? false;
    final game = r?.isGame ?? false;
    if (r == null) {
      headline = at('смотрим, читаем и играем вместе', 'watch, read and play together');
      sub = at('общая комната: видео, книги, манга и игры, голос, чат и реакции — всё в одном месте',
          'a shared room: video, books, manga and games, voice, chat and reactions in one place');
      button = at('начать', 'start');
    } else if (here.isNotEmpty) {
      final names = here.map((p) => p.name.toLowerCase()).join(', ');
      headline = r.isLive
          ? (reading
              ? at('$names уже читают', '$names are reading')
              : game
                  ? at('$names уже играют', '$names are playing')
                  : at('$names уже смотрят', '$names are watching'))
          : at('$names ждут вас', '$names are waiting');
      sub = r.title;
      button = at('войти', 'join');
    } else if (iAmIn) {
      headline = at('ваша комната открыта', 'your room is open');
      sub = r.title;
      button = at('вернуться', 'return');
    } else {
      headline = at('комната открыта', 'a room is open');
      sub = r.title;
      button = at('войти', 'join');
    }

    return PressScale(
      haptics: true,
      scaleTo: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: ClayBoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withOpacity(0.20), SeenlyPalette.paper),
              Color.alphaBlend(SeenlyPalette.pink.withOpacity(0.14), SeenlyPalette.paper),
            ],
          ),
          clayBase: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: accent.withOpacity(0.45), width: 1.4),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.live_tv_rounded, size: 15, color: accent),
                    const SizedBox(width: 6),
                    Text(at('гостиная', 'the lounge'), style: SeenlyText.serif(size: 12.5, italic: true, color: accent)),
                    if (live) ...[
                      const SizedBox(width: 8),
                      _LiveDot(color: accent),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Text(headline, style: SeenlyText.serif(size: 22, weight: FontWeight.w700, color: SeenlyPalette.ink), maxLines: 2),
                  const SizedBox(height: 6),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                      decoration: ClayBoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          reading ? Icons.menu_book_rounded : (game ? Icons.sports_esports_rounded : Icons.play_arrow_rounded),
                          size: 19,
                          color: SeenlyPalette.accentOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(button, style: SeenlyText.serif(size: 15.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent)),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    if (here.isNotEmpty) _Faces(people: here),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Breathe(
              period: const Duration(milliseconds: 4200),
              minScale: 0.94,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.14),
                  border: Border.all(color: accent.withOpacity(0.35)),
                ),
                child: Icon(
                  live
                      ? (reading ? Icons.auto_stories_rounded : (game ? Icons.sports_esports_rounded : Icons.groups_rounded))
                      : Icons.movie_filter_rounded,
                  size: 34,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faces extends StatelessWidget {
  final List<RoomParticipant> people;
  const _Faces({required this.people});

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    return SizedBox(
      width: 26.0 + (shown.length - 1) * 20,
      height: 30,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * 20.0,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SeenlyPalette.paper, width: 2)),
              child: UserAvatar(
                avatarUrl: shown[i].avatarUrl,
                avatarPreset: shown[i].avatarPreset,
                fallbackLetter: shown[i].letter,
                size: 26,
              ),
            ),
          ),
      ]),
    );
  }
}

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: widget.color.withOpacity(0.5 * _c.value), blurRadius: 8, spreadRadius: 2 * _c.value)],
          ),
        ),
      );
}

class _PendingReviewCard extends StatelessWidget {
  final CircleReview review;
  final VoidCallback onTap;
  const _PendingReviewCard({required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final others = review.people.where((p) => !p.isYou && p.done).length;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SeenlyPalette.pink.withOpacity(0.45)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: SeenlyPalette.pink.withOpacity(0.16), shape: BoxShape.circle),
            child: Icon(Icons.mark_email_unread_rounded, size: 21, color: SeenlyPalette.pink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(at('оценим вместе?', 'rate it together?'), style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                others > 0
                    ? at('«${review.title}» · кто-то уже написал свою часть', '“${review.title}” · someone already wrote their part')
                    : at('«${review.title}» · напишите свою часть', '“${review.title}” · write your part'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint),
        ]),
      ),
    );
  }
}


/// "рецензия открылась ✨": everyone has written, and you haven't looked yet.
/// Opening it plays the finale once; after that this card is gone.
class _ReadyReviewCard extends StatelessWidget {
  final CircleReview review;
  final VoidCallback onTap;
  const _ReadyReviewCard({required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avg = review.summary?.average;
    return PressScale(
      haptics: true,
      onTap: onTap,
      scaleTo: 0.985,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          gradient: LinearGradient(colors: [
            Color.alphaBlend(SeenlyPalette.accent.withOpacity(0.16), SeenlyPalette.paper),
            Color.alphaBlend(SeenlyPalette.pink.withOpacity(0.14), SeenlyPalette.paper),
          ]),
          clayBase: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SeenlyPalette.accent.withOpacity(0.45)),
        ),
        child: Row(children: [
          Breathe(
            period: const Duration(milliseconds: 2600),
            minScale: 0.9,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SeenlyPalette.accent.withOpacity(0.16), shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome_rounded, size: 21, color: SeenlyPalette.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(at('рецензия открылась ✨', 'your review is open ✨'),
                  style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                avg != null
                    ? at('«${review.title}» · общая оценка ${avg.toStringAsFixed(1)} — посмотреть',
                        '“${review.title}” · together ${avg.toStringAsFixed(1)} — take a look')
                    : at('«${review.title}» — посмотреть', '“${review.title}” — take a look'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint),
        ]),
      ),
    );
  }
}
