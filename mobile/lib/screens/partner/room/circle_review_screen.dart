import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/circle_review.dart';
import '../../../services/api_client.dart';
import '../../../services/circle_review_service.dart';
import '../../../services/diary_service.dart';
import '../../../services/error_text.dart';
import '../../../services/premium_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/mood_tag_picker.dart';
import '../../../widgets/premium_upsell_sheet.dart';
import '../../../widgets/themed_loading_indicator.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/verdict_rating.dart';
import '../../../widgets/wow_motion.dart';
import 'room_strings.dart';
import 'together_finale.dart';

/// "рецензия круга" — the joint review of an evening watched together. The
/// same screen serves a finished co-view room (it opens right after the
/// celebration) and any evening logged "watched with" (it opens from the
/// soft "оценим вместе?" card).
///
/// Three states, one screen:
///  * **писать** — my own rating, tags and a line. Nobody else's is shown.
///  * **ждём** — mine is sealed; the others are little envelopes that open
///    as they finish. It checks again every few seconds and on pull.
///  * **открыто** — everyone's part, side by side, a one-line verdict, the
///    tags you share, and (premium) the timeline of the film's moments.
///    The opening plays once per person, then it's just a page.
///
/// Reading is free forever; writing is free too — only the moments timeline
/// is premium, and a locked one is a quiet card, not a wall.
class CircleReviewScreen extends StatefulWidget {
  final String? reviewId;
  final String? roomId;
  final String? diaryEntryId;
  final String? title;
  final String? posterUrl;
  final int? momentsDurationMs;
  const CircleReviewScreen({
    super.key,
    this.reviewId,
    this.roomId,
    this.diaryEntryId,
    this.title,
    this.posterUrl,
    this.momentsDurationMs,
  });

  @override
  State<CircleReviewScreen> createState() => _CircleReviewScreenState();
}

class _CircleReviewScreenState extends State<CircleReviewScreen> {
  late final CircleReviewService _service = CircleReviewService(ApiClient.instance);
  late final DiaryService _diary = DiaryService(ApiClient.instance);

  CircleReview? _review;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  int _rating = 0;
  List<String> _tags = [];
  final _line = TextEditingController();

  bool _editing = false; // re-opening my sealed part before the review opens
  bool _playOpening = false; // the one-time reveal
  bool _openingDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _line.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      CircleReview? r;
      if (widget.reviewId != null) {
        r = await _service.get(widget.reviewId!);
      } else if (widget.roomId != null) {
        r = await _service.byRoom(widget.roomId!);
      }
      if (!mounted) return;
      if (r == null) {
        setState(() {
          _error = at('рецензия не нашлась', 'review not found');
          _loading = false;
        });
        return;
      }
      await _apply(r);
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = describeError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _apply(CircleReview r) async {
    final firstReveal = r.revealed && !(_review?.revealed ?? false) && await _shouldPlayOpening(r.id);
    if (!mounted) return;
    setState(() {
      _review = r;
      _loading = false;
      _error = null;
      if (firstReveal) _playOpening = true;
    });
    _poll?.cancel();
    if (!r.revealed && r.iAmDone) {
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
    }
  }

  static String _seenKey(String id) => 'circle_review_opened_$id';

  Future<bool> _shouldPlayOpening(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey(id)) == true) return false;
    await prefs.setBool(_seenKey(id), true);
    return true;
  }

  void _beginEdit() {
    final me = _review?.me;
    setState(() {
      _editing = true;
      _rating = me?.rating ?? 0;
      _tags = List.of(me?.tags ?? const <String>[]);
      _line.text = me?.line ?? '';
    });
  }

  Future<void> _submit() async {
    final r = _review;
    if (r == null || _sending) return;
    final line = _line.text.trim();
    if (_rating == 0 && _tags.isEmpty && line.isEmpty) {
      _toast(at('добавьте оценку, теги или пару слов — или пропустите', 'add a rating, tags or a few words — or skip'));
      return;
    }
    setState(() => _sending = true);
    try {
      final next = await _service.putMine(
        r.id,
        rating: _rating == 0 ? null : _rating,
        tags: _tags,
        line: line.isEmpty ? null : line,
      );
      // My own diary entry for the evening carries the same rating and tags,
      // so the personal diary and the joint review never disagree. The note
      // is left alone — that one is private writing, not part of this.
      final diaryId = widget.diaryEntryId;
      if (diaryId != null && (_rating > 0 || _tags.isNotEmpty)) {
        try {
          await _diary.updateEntry(
            diaryId,
            rating: _rating == 0 ? null : _rating,
            moodTags: _tags.isEmpty ? null : _tags,
          );
        } catch (_) {
          // The review is saved either way; the diary can be edited later.
        }
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _editing = false);
      await _apply(next);
    } catch (e) {
      _toast(describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _skip() async {
    final r = _review;
    if (r == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _apply(await _service.skip(r.id));
    } catch (e) {
      _toast(describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _review;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Row(children: [
                PressScale(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    at('рецензия вечера', 'review of the evening'),
                    style: SeenlyText.serif(size: 17, weight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.inkMuted)),
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: Duration(milliseconds: MediaQuery.of(context).disableAnimations ? 1 : 420),
                          child: r!.revealed
                              ? _Opened(
                                  key: const ValueKey('open'),
                                  review: r,
                                  play: _playOpening && !_openingDone,
                                  onPlayed: () => setState(() => _openingDone = true),
                                  durationMs: widget.momentsDurationMs,
                                )
                              : (r.iAmDone && !_editing)
                                  ? _Waiting(
                                      key: const ValueKey('wait'),
                                      review: r,
                                      onRefresh: () => _load(silent: true),
                                      onEdit: _beginEdit,
                                    )
                                  : _Compose(
                                      key: const ValueKey('compose'),
                                      review: r,
                                      posterUrl: widget.posterUrl ?? r.posterUrl,
                                      title: widget.title ?? r.title,
                                      rating: _rating,
                                      tags: _tags,
                                      line: _line,
                                      sending: _sending,
                                      editing: _editing,
                                      onRating: (v) => setState(() => _rating = v),
                                      onTags: (t) => setState(() => _tags = t),
                                      onSubmit: _submit,
                                      onSkip: _skip,
                                    ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- writing ------------------------------------------------------------------

class _Compose extends StatelessWidget {
  final CircleReview review;
  final String? posterUrl;
  final String title;
  final int rating;
  final List<String> tags;
  final TextEditingController line;
  final bool sending;
  final bool editing;
  final ValueChanged<int> onRating;
  final ValueChanged<List<String>> onTags;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  const _Compose({
    super.key,
    required this.review,
    required this.posterUrl,
    required this.title,
    required this.rating,
    required this.tags,
    required this.line,
    required this.sending,
    required this.editing,
    required this.onRating,
    required this.onTags,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        Entrance(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (posterUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 92,
                    child: FadeInNetworkImage(url: posterUrl!, placeholder: ColoredBox(color: SeenlyPalette.cork)),
                  ),
                ),
              if (posterUrl != null) const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SeenlyText.serif(size: 20, weight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      at('напишите свою часть. остальные её не увидят, пока не напишут свою',
                          'write your part. the others won’t see it until they’ve written theirs'),
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Entrance(
          delay: const Duration(milliseconds: 90),
          child: _SealedFaces(people: review.people),
        ),
        const SizedBox(height: 22),
        Entrance(
          delay: const Duration(milliseconds: 160),
          child: Center(
            child: VerdictRating(
              value: rating,
              onChanged: onRating,
              idleLabel: at('коснитесь сердечка', 'tap a heart'),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Entrance(
          delay: const Duration(milliseconds: 230),
          child: MoodTagPicker(selected: tags, onChanged: onTags, rating: rating),
        ),
        const SizedBox(height: 22),
        Entrance(
          delay: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: clayWellDecoration(radius: 22),
            child: TextField(
              controller: line,
              maxLength: 280,
              minLines: 2,
              maxLines: 4,
              style: SeenlyText.serif(size: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: at('одна фраза о вечере — по желанию', 'one line about the evening — optional'),
                hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        PressScale(
          haptics: true,
          onTap: sending ? null : onSubmit,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            alignment: Alignment.center,
            decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
            child: sending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                  )
                : Text(
                    editing ? at('обновить мою часть', 'update my part') : at('запечатать мою часть', 'seal my part'),
                    style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: PressScale(
            onTap: sending ? null : onSkip,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(at('не хочу оценивать', 'I’d rather not'),
                  style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkFaint)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The people of the evening as small faces with a tiny seal that fills in
/// as each finishes.
class _SealedFaces extends StatelessWidget {
  final List<ReviewPerson> people;
  const _SealedFaces({required this.people});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final p in people)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                UserAvatar(avatarUrl: p.avatarUrl, avatarPreset: p.avatarPreset, fallbackLetter: p.letter, size: 44),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutBack,
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: p.done ? SeenlyPalette.sage : SeenlyPalette.paper,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.done ? SeenlyPalette.sage : SeenlyPalette.border, width: 1.5),
                    ),
                    child: Icon(
                      p.done ? Icons.mark_email_read_rounded : Icons.edit_outlined,
                      size: 11,
                      color: p.done ? Colors.white : SeenlyPalette.inkFaint,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(p.isYou ? at('вы', 'you') : p.name.toLowerCase(),
                  style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkMuted)),
            ]),
          ),
      ],
    );
  }
}

// --- waiting ------------------------------------------------------------------

class _Waiting extends StatelessWidget {
  final CircleReview review;
  final Future<void> Function() onRefresh;
  final VoidCallback onEdit;
  const _Waiting({super.key, required this.review, required this.onRefresh, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final waiting = review.waitingOn;
    final names = waiting.map((p) => p.name.toLowerCase()).join(', ');
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 40, 22, 32),
        children: [
          Center(
            child: Breathe(
              child: Container(
                width: 112,
                height: 112,
                decoration: ClayBoxDecoration(
                  color: SeenlyPalette.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: SeenlyPalette.border),
                  boxShadow: SeenlyPalette.softShadow,
                ),
                child: Icon(Icons.mark_email_unread_rounded, size: 48, color: SeenlyPalette.accent),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              at('ваша часть запечатана', 'your part is sealed'),
              style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              waiting.isEmpty
                  ? at('открываем…', 'opening…')
                  : at('ждём: $names. как только напишут — рецензия откроется у всех сразу',
                      'waiting for: $names. as soon as they write, it opens for everyone'),
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.inkMuted),
            ),
          ),
          const SizedBox(height: 26),
          _SealedFaces(people: review.people),
          if (review.me?.rating != null) ...[
            const SizedBox(height: 18),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: SeenlyPalette.pink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.favorite_rounded, size: 15, color: SeenlyPalette.pink),
                  const SizedBox(width: 6),
                  Text(at('ваша оценка ${review.me!.rating}', 'your rating ${review.me!.rating}'),
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.pink)),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: PressScale(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(at('дописать фразу или поправить', 'add a line or change it'),
                    style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.accent)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              at('если кто-то не успеет за неделю, рецензия откроется сама',
                  'if someone doesn’t get to it within a week, it opens on its own'),
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

// --- opened -------------------------------------------------------------------

class _Opened extends StatefulWidget {
  final CircleReview review;
  final bool play;
  final VoidCallback onPlayed;
  final int? durationMs;
  const _Opened({super.key, required this.review, required this.play, required this.onPlayed, this.durationMs});

  @override
  State<_Opened> createState() => _OpenedState();
}

class _OpenedState extends State<_Opened> {
  int _shown = 0; // how many people's cards are open
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.play && !reduce) {
      _shown = 0;
      _t = Timer.periodic(const Duration(milliseconds: 650), (t) {
        if (!mounted) return t.cancel();
        setState(() => _shown++);
        HapticFeedback.selectionClick();
        if (_shown >= widget.review.people.length + 1) {
          t.cancel();
          widget.onPlayed();
        }
      });
    } else {
      _shown = 1 << 20;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final people = r.people;
    final s = r.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        Center(
          child: Text(r.title, textAlign: TextAlign.center, style: SeenlyText.serif(size: 21, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < people.length; i++)
          _PersonCard(person: people[i], open: _shown > i, delayIndex: i),
        const SizedBox(height: 8),
        if (s != null && s.average != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: SeenlyPalette.accent.withOpacity(0.4)),
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: TogetherFinale(
                hearts: [
                  for (final p in people)
                    if (p.rating != null) FinaleHeart(name: p.name, rating: p.rating!, isYou: p.isYou),
                ],
                average: s.average,
                verdict: s.verdict,
                sharedTags: s.sharedTags,
                animate: widget.play,
                active: _shown > people.length,
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (r.origin == 'room' && (r.moments != null || r.momentsLocked))
          AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: _shown > people.length ? 1 : 0,
            child: r.moments != null
                ? _MomentsTimeline(
                    moments: r.moments!,
                    durationMs: widget.durationMs,
                    reading: _isReading(r.mediaType),
                    game: r.mediaType == 'game',
                  )
                : _MomentsLocked(reading: _isReading(r.mediaType), game: r.mediaType == 'game'),
          ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  final ReviewPerson person;
  final bool open;
  final int delayIndex;
  const _PersonCard({required this.person, required this.open, required this.delayIndex});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduce ? 1 : 520),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: open
          ? Container(
              key: ValueKey('open_${person.userId}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.paper,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: SeenlyPalette.border),
                boxShadow: SeenlyPalette.flatCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    UserAvatar(avatarUrl: person.avatarUrl, avatarPreset: person.avatarPreset, fallbackLetter: person.letter, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(person.isYou ? at('вы', 'you') : person.name.toLowerCase(),
                          style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600)),
                    ),
                    if (person.rating != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.favorite_rounded, size: 17, color: SeenlyPalette.pink),
                        const SizedBox(width: 4),
                        Text('${person.rating}', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: SeenlyPalette.pink)),
                        Text(' / 10', style: SeenlyText.mono(size: 12)),
                      ]),
                  ]),
                  if (person.skipped || (person.rating == null && person.tags.isEmpty && (person.line ?? '').isEmpty)) ...[
                    const SizedBox(height: 10),
                    Text(
                      person.done
                          ? at('промолчал(а) — и так бывает', 'stayed quiet — that happens')
                          : at('так и не успел(а) написать', 'never got around to it'),
                      style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkFaint),
                    ),
                  ],
                  if (person.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final t in person.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(t, style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.accent)),
                        ),
                    ]),
                  ],
                  if ((person.line ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('“${person.line}”', style: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.ink)),
                  ],
                ],
              ),
            )
          : Container(
              key: ValueKey('sealed_${person.userId}'),
              margin: const EdgeInsets.only(bottom: 12),
              height: 78,
              alignment: Alignment.center,
              decoration: ClayBoxDecoration(
                color: SeenlyPalette.cork,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: SeenlyPalette.dashedBorder),
              ),
              child: Icon(Icons.mail_rounded, color: SeenlyPalette.inkFaint, size: 30),
            ),
    );
  }
}

/// A book or a manga: its moments are places in the text, not minutes.
bool _isReading(String mediaType) => mediaType == 'book' || mediaType == 'manga';

class _MomentsLocked extends StatelessWidget {
  final bool reading;

  /// A game: its moments are the rounds you played and what you reacted to, on
  /// the session clock — a time, like a film's.
  final bool game;
  const _MomentsLocked({this.reading = false, this.game = false});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => showPremiumUpsellSheet(
        context,
        triggerSource: 'co_view_moments',
        initialKind: PremiumPlanKind.couple,
        icon: Icons.timeline_rounded,
        title: reading
            ? at('моменты вашего чтения', 'your reading’s moments')
            : game
                ? at('моменты вашей игры', 'your game’s moments')
                : at('моменты вашего фильма', 'your film’s moments'),
        message: reading
            ? at(
                'мы запомнили, где вы вместе смеялись, ахали и писали на полях. '
                    'с подпиской — шкала моментов появится здесь, и всё, что вы уже отметили, тоже',
                'we remember where you laughed, gasped and wrote in the margin together. '
                    'with a subscription the timeline appears here — including everything you already marked',
              )
            : game
                ? at(
                    'мы запомнили ваши победы, поражения и то, над чем вы вместе смеялись или вопили. '
                        'с подпиской — шкала моментов появится здесь, и всё, что вы уже отметили, тоже',
                    'we remember your wins, your losses and what made you laugh or yell together. '
                        'with a subscription the timeline appears here — including everything you already marked',
                  )
                : at(
                    'мы запомнили, где вы вместе смеялись, ахали и тянулись за платком. '
                        'с подпиской — шкала моментов появится здесь, и всё, что вы уже отметили, тоже',
                    'we remember where you laughed, gasped and reached for a tissue together. '
                        'with a subscription the timeline appears here — including everything you already tapped',
                  ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SeenlyPalette.cork.withOpacity(0.6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SeenlyPalette.dashedBorder),
        ),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 20, color: SeenlyPalette.inkFaint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              reading
                  ? at('моменты чтения: где вы реагировали вместе — с подпиской', 'reading moments: where you reacted together — with a subscription')
                  : game
                      ? at('моменты игры: победы, поражения и общие реакции — с подпиской', 'game moments: wins, losses and shared reactions — with a subscription')
                      : at('моменты фильма: где вы реагировали вместе — с подпиской', 'film moments: where you reacted together — with a subscription'),
              style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MomentsTimeline extends StatelessWidget {
  final List<ReviewMoment> moments;
  final int? durationMs;

  /// A book or a manga: places are shown as how far through the text they
  /// are ("41%"), not as a clock. (The server scales a reading room's
  /// progress by 1000 so the same timeline maths works — see co_reading.py.)
  final bool reading;

  /// A game: the same clock a film has (the session timer), titled for the game.
  final bool game;
  const _MomentsTimeline({required this.moments, this.durationMs, this.reading = false, this.game = false});

  /// A film's moment is a time; a book's is where in it: "глава 4 · 41%",
  /// "стр. 43 · 23%" (the place the server kept, plus how far through).
  String _place(ReviewMoment m) {
    if (!reading) return clockLabel(m.positionMs);
    final pct = '${(m.positionMs / 10000).round().clamp(0, 100)}%';
    final loc = m.locator;
    if (loc == null) return pct;
    final chapter = RegExp(r'^c(\d+)').firstMatch(loc);
    if (chapter != null) return '${at('глава', 'ch.')} ${int.parse(chapter.group(1)!) + 1} · $pct';
    final page = RegExp(r'^p(\d+)$').firstMatch(loc);
    if (page != null) return '${at('стр.', 'p.')} ${int.parse(page.group(1)!) + 1} · $pct';
    return pct;
  }

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) return const SizedBox.shrink();
    final last = moments.map((m) => m.positionMs).reduce((a, b) => a > b ? a : b);
    final total = (durationMs != null && durationMs! > 0) ? durationMs! : (last * 1.12).round().clamp(60000, 1 << 30);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            reading
                ? at('моменты чтения', 'reading moments')
                : game
                    ? at('моменты игры', 'game moments')
                    : at('моменты фильма', 'film moments'),
            style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600)),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                Container(height: 4, decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2))),
                for (final m in moments)
                  Positioned(
                    left: (w * (m.positionMs / total).clamp(0.0, 1.0)) - (m.shared ? 15 : 11),
                    child: Container(
                      width: m.shared ? 30 : 22,
                      height: m.shared ? 30 : 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: m.shared ? SeenlyPalette.pink.withOpacity(0.2) : SeenlyPalette.cork,
                        shape: BoxShape.circle,
                        border: Border.all(color: m.shared ? SeenlyPalette.pink : SeenlyPalette.border, width: 1.5),
                      ),
                      child: Text(_glyph(m.top), style: TextStyle(fontSize: m.shared ? 15 : 11)),
                    ),
                  ),
              ]);
            },
          ),
        ),
        const SizedBox(height: 8),
        for (final m in moments.where((m) => m.shared))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Text(_place(m), style: SeenlyText.mono(size: 12.5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  at('вы вместе: ${_glyph(m.top)}', 'together: ${_glyph(m.top)}'),
                  style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.ink),
                ),
              ),
            ]),
          ),
        if (!moments.any((m) => m.shared))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(at('каждый реагировал в своих местах', 'each of you reacted in your own places'),
                style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkFaint)),
          ),
      ]),
    );
  }

  /// A reaction key is either an emoji or one of the emotion words.
  static String _glyph(String key) {
    const emotions = ['warm', 'funny', 'tense', 'touching', 'beautiful', 'sad', 'wow', 'bored'];
    return emotions.contains(key) ? emotionEmoji(key) : key;
  }
}
