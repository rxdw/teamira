import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/circle_review.dart';
import '../../../models/media_item.dart';
import '../../../services/api_client.dart';
import '../../../services/circle_review_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'circle_review_screen.dart';
import 'room_strings.dart';
import 'together_finale.dart';

/// What appears under the "kept" ritual right after you log an evening
/// "watched with" someone — the joint rating, live.
///
/// Your own rating from the log is already sealed as your part. Then, one of:
///  * the others haven't rated yet → a small sealed-envelope card: your heart
///    with its number, soft breathing placeholders for the others, and a
///    quiet "дописать фразу" (it keeps checking, so the moment they rate it
///    opens right here, while you're still looking at the screen);
///  * everyone has → the finale plays: hearts drift together and melt into
///    one, the shared number counts up, the verdict line and common tags land;
///  * you logged without a rating → a gentle "оценим вместе?" invitation.
/// It draws nothing when there is no review (logged alone, or not linked).
class TogetherVerdictCard extends StatefulWidget {
  final MediaItem item;

  /// A review already fetched by the caller, so the card has something to
  /// draw from its very first frame.
  final CircleReview? initial;
  const TogetherVerdictCard({super.key, required this.item, this.initial});

  @override
  State<TogetherVerdictCard> createState() => _TogetherVerdictCardState();
}

class _TogetherVerdictCardState extends State<TogetherVerdictCard> {
  final _service = CircleReviewService(ApiClient.instance);
  CircleReview? _review;
  bool _loaded = false;
  bool _animateFinale = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final first = widget.initial;
    if (first != null) {
      _review = first;
      _loaded = true;
      _animateFinale = first.revealed;
      if (first.revealed) _rememberOpened(first.id);
      if (!first.revealed && first.iAmDone) {
        _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
      }
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _rememberOpened(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey(id), true);
  }

  static String _seenKey(String id) => 'circle_review_opened_$id';

  Future<void> _load() async {
    try {
      final r = await _service.byTitle(widget.item.source, widget.item.id);
      if (!mounted) return;
      var animate = _animateFinale;
      if (r != null && r.revealed && !(_review?.revealed ?? false)) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_seenKey(r.id)) != true) {
          await prefs.setBool(_seenKey(r.id), true);
          animate = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _review = r;
        _loaded = true;
        _animateFinale = animate;
      });
      _poll?.cancel();
      if (r != null && !r.revealed && r.iAmDone) {
        _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
      }
    } catch (_) {
      if (mounted && !_loaded) setState(() => _loaded = true);
    }
  }

  Future<void> _openReview() async {
    final r = _review;
    if (r == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CircleReviewScreen(reviewId: r.id, title: r.title, posterUrl: r.posterUrl),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _review;
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedSize(
      duration: Duration(milliseconds: reduce ? 1 : 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 1 : 420),
        child: !_loaded || r == null
            ? const SizedBox(key: ValueKey('none'), width: double.infinity)
            : r.revealed
                ? _Revealed(key: ValueKey('rev_${r.id}'), review: r, animate: _animateFinale, onOpen: _openReview)
                : r.iAmDone
                    ? _Sealed(key: ValueKey('seal_${r.id}'), review: r, onTap: _openReview)
                    : _Invite(key: ValueKey('inv_${r.id}'), review: r, onTap: _openReview),
      ),
    );
  }
}

Widget _shell({required Widget child, Color? accent}) => Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: (accent ?? SeenlyPalette.border).withOpacity(accent == null ? 1 : 0.45)),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: child,
    );

class _Invite extends StatelessWidget {
  final CircleReview review;
  final VoidCallback onTap;
  const _Invite({super.key, required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: _shell(
        accent: SeenlyPalette.pink,
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: SeenlyPalette.pink.withOpacity(0.16), shape: BoxShape.circle),
            child: Icon(Icons.favorite_border_rounded, size: 21, color: SeenlyPalette.pink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(at('оценим вместе?', 'rate it together?'), style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(at('поставьте оценку — общая появится, когда оценят все', 'rate it — the shared one appears when everyone has'),
                  style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint),
        ]),
      ),
    );
  }
}

class _Sealed extends StatelessWidget {
  final CircleReview review;
  final VoidCallback onTap;
  const _Sealed({super.key, required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final waiting = review.waitingOn;
    final names = waiting.map((p) => p.name.toLowerCase()).join(', ');
    final me = review.me;
    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: _shell(
        accent: SeenlyPalette.sage,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final p in review.people) ...[
              _Face(person: p),
              if (p != review.people.last) const SizedBox(width: 6),
              if (p != review.people.last)
                Breathe(
                  period: const Duration(milliseconds: 2400),
                  minScale: 0.9,
                  child: Icon(Icons.favorite_rounded, size: 14, color: SeenlyPalette.pink.withOpacity(0.7)),
                ),
              if (p != review.people.last) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 12),
          Text(
            waiting.isEmpty ? at('открываем…', 'opening…') : at('ждём $names', 'waiting for $names'),
            style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            at('ваша оценка${me?.rating != null ? ' ${me!.rating}' : ''} запечатана — общая появится, как только оценят все',
                'your rating${me?.rating != null ? ' ${me!.rating}' : ''} is sealed — the shared one appears as soon as everyone has rated'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 8),
          Text(at('дописать фразу', 'add a line'),
              style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.accent)),
        ]),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  final ReviewPerson person;
  const _Face({required this.person});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        Opacity(
          opacity: person.done ? 1 : 0.55,
          child: UserAvatar(avatarUrl: person.avatarUrl, avatarPreset: person.avatarPreset, fallbackLetter: person.letter, size: 40),
        ),
        Positioned(
          right: -5,
          bottom: -5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: person.done ? SeenlyPalette.sage : SeenlyPalette.paper,
              shape: BoxShape.circle,
              border: Border.all(color: person.done ? SeenlyPalette.sage : SeenlyPalette.border, width: 1.5),
            ),
            child: Icon(
              person.done ? Icons.lock_rounded : Icons.more_horiz_rounded,
              size: 11,
              color: person.done ? Colors.white : SeenlyPalette.inkFaint,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 5),
      Text(person.isYou ? at('вы', 'you') : person.name.toLowerCase(),
          style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkMuted)),
    ]);
  }
}

class _Revealed extends StatelessWidget {
  final CircleReview review;
  final bool animate;
  final VoidCallback onOpen;
  const _Revealed({super.key, required this.review, required this.animate, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = review.summary;
    final hearts = [
      for (final p in review.people)
        if (p.rating != null) FinaleHeart(name: p.name, rating: p.rating!, isYou: p.isYou),
    ];
    if (s == null || s.average == null || hearts.isEmpty) {
      return const SizedBox(width: double.infinity);
    }
    return _shell(
      accent: SeenlyPalette.accent,
      child: Column(children: [
        TogetherFinale(
          hearts: hearts,
          average: s.average,
          verdict: s.verdict,
          sharedTags: s.sharedTags,
          animate: animate,
        ),
        const SizedBox(height: 10),
        PressScale(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(at('открыть рецензию', 'open the review'),
                style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.accent)),
          ),
        ),
      ]),
    );
  }
}

/// The joint rating in its own soft sheet, shown right after logging an
/// evening "watched with" someone — one pattern for every log screen.
///
/// Shown only when there is a review to show (you logged with a linked
/// partner); otherwise it quietly does nothing. If the others have already
/// rated it opens straight into the finale; if not, it says your rating is
/// sealed and keeps watching, so the finale can play right here the moment
/// they rate.
Future<void> showTogetherVerdictSheet(BuildContext context, MediaItem item) async {
  CircleReview? review;
  try {
    review = await CircleReviewService(ApiClient.instance).byTitle(item.source, item.id);
  } catch (_) {
    return;
  }
  if (review == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(at('общая оценка', 'your rating together'), style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            TogetherVerdictCard(item: item, initial: review),
            PressScale(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
                child: Text(at('готово', 'done'),
                    style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
