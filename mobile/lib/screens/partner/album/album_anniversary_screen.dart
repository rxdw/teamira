import 'dart:math' as math;

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
import 'album_paywall.dart';
import 'album_strings.dart';
import 'album_widgets.dart';

/// "Наша годовщина" — its own screen, not a card.
///
/// One big number (years once there's a year, days before that) inside a
/// ring that fills toward the next anniversary, the two of you above it,
/// and underneath: the next milestone, the first evening you watched
/// together, and how many evenings there've been since.
///
/// The date is either set by one of the two (last write wins, the other is
/// told who changed it) or absent, in which case the screen is an
/// invitation to set it — offering the day you linked accounts as a
/// starting point, never assuming it's the anniversary.
///
/// On the day itself — an anniversary or a day-count milestone — confetti
/// falls once when the screen opens.
class AlbumAnniversaryScreen extends StatefulWidget {
  final AlbumStatus status;
  const AlbumAnniversaryScreen({super.key, required this.status});

  @override
  State<AlbumAnniversaryScreen> createState() => _AlbumAnniversaryScreenState();
}

const Color _roseTop = Color(0xFF3B1A3A);
const Color _roseBottom = Color(0xFF7A3358);

class _AlbumAnniversaryScreenState extends State<AlbumAnniversaryScreen> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);

  late AlbumStatus _status = widget.status;
  bool _saving = false;
  bool _confetti = false;

  @override
  void initState() {
    super.initState();
    _maybeCelebrate();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await _service.status();
      if (!mounted) return;
      final hadDate = _status.togetherSince != null;
      setState(() => _status = fresh);
      if (!hadDate) _maybeCelebrate();
    } catch (_) {
      // The status we were opened with is still good enough to show.
    }
  }

  bool get _isBigDay {
    final since = _status.togetherSince;
    if (since == null) return false;
    final today = _status.serverToday;
    return isAnniversaryToday(since, today) || milestoneToday(since, today) != null;
  }

  void _maybeCelebrate() {
    if (!_isBigDay || _confetti) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _confetti = true);
    });
  }

  Future<void> _pickDate() async {
    if (!_status.isPremium) {
      await showAlbumPaywall(
        context,
        kind: AlbumPaywallKind.anniversary,
        source: 'pair_album_anniversary',
      );
      return;
    }
    final today = _status.serverToday;
    final picked = await showDatePicker(
      context: context,
      initialDate: _status.togetherSince ?? _status.linkedOn ?? today,
      firstDate: DateTime(today.year - 60),
      lastDate: today,
      helpText: at('когда всё началось?', 'when did it start?'),
    );
    if (picked == null || !mounted) return;
    await _save(DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save(DateTime? day) async {
    setState(() => _saving = true);
    try {
      final fresh = await _service.setTogetherSince(day);
      if (!mounted) return;
      setState(() {
        _status = fresh;
        _saving = false;
      });
      HapticFeedback.mediumImpact();
      _maybeCelebrate();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (PairAlbumService.isPaywall(e)) {
        await showAlbumPaywall(
          context,
          kind: AlbumPaywallKind.anniversary,
          source: 'pair_album_anniversary',
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final since = _status.togetherSince;
    return Scaffold(
      backgroundColor: _roseTop,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_roseTop, _roseBottom],
                ),
              ),
            ),
          ),
          Positioned.fill(child: AlbumSparks(color: SeenlyPalette.pink, count: 22, opacity: 0.8)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      ),
                      const Spacer(),
                      if (since != null)
                        IconButton(
                          tooltip: at('изменить дату', 'change the date'),
                          onPressed: _saving ? null : _pickDate,
                          icon: const Icon(Icons.edit_calendar_rounded, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    child: since == null ? _setup(context) : _celebration(context, since),
                  ),
                ),
              ],
            ),
          ),
          if (_confetti) const Positioned.fill(child: AlbumConfetti(count: 70)),
        ],
      ),
    );
  }

  // --- no date yet ----------------------------------------------------

  Widget _setup(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final linked = _status.linkedOn;
    return Column(
      children: [
        const SizedBox(height: 16),
        Entrance(child: PairAvatars(people: _status.people, size: 72)),
        const SizedBox(height: 28),
        Entrance(
          delay: const Duration(milliseconds: 120),
          child: Text(
            at('когда всё началось?', 'when did it all start?'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 26, weight: FontWeight.w600, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Entrance(
          delay: const Duration(milliseconds: 220),
          child: Text(
            at(
              'выберите день — и здесь появится ваш счётчик: годы, дни, ближайшая годовщина '
                  'и праздник в каждую круглую дату',
              'pick a day and this becomes your counter: years, days, the next anniversary and '
                  'a little celebration on every round number',
            ),
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 12.5, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 34),
        Entrance(
          delay: const Duration(milliseconds: 340),
          child: ClayButton(
            label: at('выбрать дату', 'pick the date'),
            icon: Icons.favorite_rounded,
            loading: _saving,
            color: SeenlyPalette.coral,
            onTap: _pickDate,
          ),
        ),
        if (linked != null) ...[
          const SizedBox(height: 10),
          Entrance(
            delay: const Duration(milliseconds: 440),
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      if (!_status.isPremium) {
                        showAlbumPaywall(
                          context,
                          kind: AlbumPaywallKind.anniversary,
                          source: 'pair_album_anniversary',
                        );
                        return;
                      }
                      _save(linked);
                    },
              child: Text(
                at(
                  'или считать с ${albumDateLabel(linked, ru: ru)} — когда вы связали аккаунты',
                  'or count from ${albumDateLabel(linked, ru: ru)} — when you linked accounts',
                ),
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 12, color: Colors.white60),
              ),
            ),
          ),
        ],
        if (!_status.isPremium) ...[
          const SizedBox(height: 18),
          Text(
            at('годовщина — часть альбома пары', 'the anniversary is part of the pair album'),
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 11.5, color: Colors.white54),
          ),
        ],
      ],
    );
  }

  // --- the celebration ------------------------------------------------

  Widget _celebration(BuildContext context, DateTime since) {
    final ru = LocaleService.appIsRussian;
    final today = _status.serverToday;
    final years = fullYears(since, today);
    final days = daysTogether(since, today);
    final progress = yearProgress(since, today);
    final annivToday = isAnniversaryToday(since, today);
    final milestone = milestoneToday(since, today);
    final next = nextAnniversary(since, today);
    final daysToNext = daysBetween(today, next);
    final nextMilestone = nextDayMilestone(since, today);
    final setBy = _status.togetherSetBy;
    final me = _status.me;
    final changedByPartner = setBy != null && me != null && setBy != me.username;

    final bigNumber = years >= 1 ? years : days;
    final bigLabel = years >= 1 ? yearsLabel(years).split(' ').last : daysLabel(days).split(' ').last;

    return Column(
      children: [
        const SizedBox(height: 4),
        Entrance(child: PairAvatars(people: _status.people, size: 62)),
        const SizedBox(height: 22),
        if (annivToday || milestone != null)
          Entrance(
            delay: const Duration(milliseconds: 80),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: SeenlyPalette.mustard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                annivToday
                    ? at('сегодня ваша годовщина', 'today is your anniversary')
                    : at('сегодня ${daysLabel(milestone!)} вместе', 'today: ${daysLabel(milestone!)} together'),
                style: SeenlyText.mono(size: 12.5, weight: FontWeight.w700, color: const Color(0xFF3B1A3A)),
              ),
            ),
          ),
        const SizedBox(height: 18),
        Entrance(
          delay: const Duration(milliseconds: 160),
          duration: const Duration(milliseconds: 800),
          child: SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                BreathingGlow(
                  color: SeenlyPalette.pink,
                  size: 290,
                  maxOpacity: 0.3,
                  child: const SizedBox(width: 10, height: 10),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: albumReduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1600),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => CustomPaint(
                    size: const Size.square(250),
                    painter: _HeartRingPainter(v),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CountUpNumber(
                      value: bigNumber.toDouble(),
                      decimals: 0,
                      duration: const Duration(milliseconds: 1500),
                      style: SeenlyText.serif(size: 66, weight: FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      bigLabel,
                      style: SeenlyText.serif(size: 20, weight: FontWeight.w500, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Entrance(
          delay: const Duration(milliseconds: 420),
          child: Column(
            children: [
              Text(
                at('вместе с ${albumDateLabel(since, ru: ru)}', 'together since ${albumDateLabel(since, ru: ru)}'),
                style: SeenlyText.serif(size: 16, weight: FontWeight.w500, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                years >= 1
                    ? at('это ${daysLabel(days)}', 'that\'s ${daysLabel(days)}')
                    : at('первый год вместе', 'your first year together'),
                style: SeenlyText.mono(size: 12, color: Colors.white60),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Entrance(
          delay: const Duration(milliseconds: 560),
          riseBy: 18,
          child: _GlassCard(
            icon: Icons.cake_rounded,
            title: annivToday ? at('годовщина — сегодня', 'anniversary — today') : at('следующая годовщина', 'next anniversary'),
            value: annivToday
                ? at('с праздником', 'happy anniversary')
                : at('${albumDateLabel(next, ru: ru, withYear: false)} · ${countdownLabel(daysToNext)}',
                    '${albumDateLabel(next, ru: ru, withYear: false)} · ${countdownLabel(daysToNext)}'),
            hint: annivToday
                ? null
                : at('исполнится ${yearsLabel(years + 1)}', 'you\'ll be at ${yearsLabel(years + 1)}'),
          ),
        ),
        if (nextMilestone != null) ...[
          const SizedBox(height: 12),
          Entrance(
            delay: const Duration(milliseconds: 660),
            riseBy: 18,
            child: _GlassCard(
              icon: Icons.flag_rounded,
              title: at('ближайшая круглая дата', 'next round number'),
              value: at('${daysLabel(nextMilestone.days)} вместе', '${daysLabel(nextMilestone.days)} together'),
              hint: at(
                '${albumDateLabel(nextMilestone.on, ru: ru)} · ${countdownLabel(daysBetween(today, nextMilestone.on))}',
                '${albumDateLabel(nextMilestone.on, ru: ru)} · ${countdownLabel(daysBetween(today, nextMilestone.on))}',
              ),
            ),
          ),
        ],
        if (_status.firstEvening != null) ...[
          const SizedBox(height: 12),
          Entrance(
            delay: const Duration(milliseconds: 760),
            riseBy: 18,
            child: _FirstEveningCard(evening: _status.firstEvening!, total: _status.eveningsTogether),
          ),
        ] else if (_status.eveningsTogether > 0) ...[
          const SizedBox(height: 12),
          Entrance(
            delay: const Duration(milliseconds: 760),
            riseBy: 18,
            child: _GlassCard(
              icon: Icons.movie_filter_rounded,
              title: at('вечеров вместе', 'evenings together'),
              value: '${_status.eveningsTogether}',
            ),
          ),
        ],
        if (changedByPartner) ...[
          const SizedBox(height: 22),
          Text(
            at('дату указал(а) ${_status.partner?.name ?? setBy}', 'the date was set by ${_status.partner?.name ?? setBy}'),
            style: SeenlyText.mono(size: 11, color: Colors.white38),
          ),
        ],
      ],
    );
  }
}

/// A ring that fills like a heart's outline of progress toward the next
/// anniversary — a plain arc with a soft glow, plus a marker at its head.
class _HeartRingPainter extends CustomPainter {
  final double progress;
  _HeartRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 9.0;
    final rect = Offset(stroke, stroke) & Size(size.width - stroke * 2, size.height - stroke * 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withOpacity(0.12),
    );
    if (progress <= 0.002) return;
    final sweep = math.pi * 2 * progress;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke + 8
      ..color = SeenlyPalette.pink.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + math.pi * 2,
          colors: [SeenlyPalette.mustard, SeenlyPalette.pink, SeenlyPalette.coral],
          transform: const GradientRotation(0),
        ).createShader(rect),
    );
    // A heart riding the head of the arc.
    final angle = -math.pi / 2 + sweep;
    final center = rect.center;
    final head = Offset(
      center.dx + rect.width / 2 * math.cos(angle),
      center.dy + rect.height / 2 * math.sin(angle),
    );
    canvas.drawPath(albumHeartPath(head, 17), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HeartRingPainter old) => old.progress != progress;
}

class _GlassCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? hint;
  const _GlassCard({required this.icon, required this.title, required this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SeenlyPalette.pink, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SeenlyText.mono(size: 11.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: SeenlyText.serif(size: 16.5, weight: FontWeight.w600, color: Colors.white),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: SeenlyText.mono(size: 11.5, color: Colors.white54)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstEveningCard extends StatelessWidget {
  final AlbumFirstEvening evening;
  final int total;
  const _FirstEveningCard({required this.evening, required this.total});

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final title = (ru ? (evening.titleRu ?? evening.titleEn) : (evening.titleEn ?? evening.titleRu)) ?? '—';
    final at0 = evening.watchedAt?.toLocal();
    final day = at0 == null ? null : DateTime(at0.year, at0.month, at0.day);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          AlbumPoster(url: evening.posterUrl, width: 50, radius: 8, fallback: SeenlyPalette.pink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(at('наш первый фильм вдвоём', 'our first film together'),
                    style: SeenlyText.mono(size: 11.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (day != null) albumDateLabel(day, ru: ru),
                    at('всего вечеров: $total', 'evenings so far: $total'),
                  ].join(' · '),
                  style: SeenlyText.mono(size: 11.5, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
