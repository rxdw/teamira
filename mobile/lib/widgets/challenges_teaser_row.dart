import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../screens/profile/challenges_screen.dart';
import '../services/api_client.dart';
import '../services/app_translations.dart';
import '../services/challenges_service.dart';
import '../services/locale_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'challenge_card.dart';
import 'wow_motion.dart';

/// The row that sits under Profile's "challenges" header — the same job
/// [RoundBadgeMedallion]s do under "badges" and the poster cards do under
/// "recently logged": a glanceable preview so the header isn't a title
/// floating over nothing.
///
/// Each challenge is a round medallion: its icon in the middle, a ring
/// around it that fills with progress, and underneath its title plus a
/// small "2 / 5" (or "забрать" when it's finished and waiting to be
/// collected). This week's challenges come first, then the year's.
///
/// Loads its own data (best-effort, like the badges row): a failed fetch
/// just shows a quiet line of text and never affects the rest of Profile.
class ChallengesTeaserRow extends StatefulWidget {
  const ChallengesTeaserRow({super.key});

  @override
  State<ChallengesTeaserRow> createState() => _ChallengesTeaserRowState();
}

class _ChallengesTeaserRowState extends State<ChallengesTeaserRow> {
  late final ChallengesService _service = ChallengesService(ApiClient.instance);
  Challenges? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.load(russian: LocaleService.appIsRussian);
      if (mounted) setState(() {
        _data = data;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChallengesScreen()),
    );
    // Claiming a reward over there changes what this row should show.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return SizedBox(
        height: 92,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _failed ? 'couldn\'t load challenges right now'.tr : '…',
            style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder),
          ),
        ),
      );
    }
    final all = [...data.weekly, ...data.yearly];
    if (all.isEmpty) {
      return Text(
        'new challenges are on their way'.tr,
        style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.placeholder),
      );
    }
    // Collectable ones first — they're the only ones with something to
    // do — then everything else in the backend's own order (weekly
    // before yearly).
    final ordered = [
      ...all.where((c) => c.claimable),
      ...all.where((c) => !c.claimable),
    ].take(6).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            _ChallengeMedallion(challenge: ordered[i], onTap: _open),
          ],
        ],
      ),
    );
  }
}

class _ChallengeMedallion extends StatelessWidget {
  final Challenge challenge;
  final VoidCallback onTap;
  const _ChallengeMedallion({required this.challenge, required this.onTap});

  static const double _diameter = 56;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final claimable = c.claimable;
    final done = c.completed;
    final color = claimable
        ? SeenlyPalette.mustard
        : (c.isWeekly ? SeenlyPalette.sage : SeenlyPalette.accent);

    final String caption;
    if (claimable) {
      caption = 'collect'.tr;
    } else if (done) {
      caption = '✓';
    } else {
      caption = '${c.current} / ${c.target}';
    }

    Widget medallion = SizedBox(
      width: _diameter,
      height: _diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The ring: a faint full track with the progress arc on top.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: done ? 1.0 : c.progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(
              size: const Size(_diameter, _diameter),
              painter: _RingPainter(
                progress: v,
                color: color,
                track: color.withOpacity(0.16),
              ),
            ),
          ),
          Container(
            width: _diameter - 14,
            height: _diameter - 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: claimable ? color.withOpacity(0.18) : SeenlyPalette.paper,
              boxShadow: [
                BoxShadow(
                  color: SeenlyPalette.shadowColor.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              challengeIcon(c.iconKey),
              size: 20,
              color: done && !claimable ? SeenlyPalette.inkFaint : color,
            ),
          ),
        ],
      ),
    );

    // Something to collect gets a slow breathing glow — the one state on
    // this row that's asking for a tap.
    if (claimable) {
      medallion = BreathingGlow(
        color: color,
        size: _diameter + 6,
        period: const Duration(milliseconds: 3200),
        maxOpacity: 0.22,
        child: medallion,
      );
    }

    return PressScale(
      onTap: onTap,
      scaleTo: 0.94,
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            medallion,
            const SizedBox(height: 7),
            Text(
              c.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(
                size: 11,
                italic: true,
                color: done && !claimable ? SeenlyPalette.inkFaint : SeenlyPalette.inkMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              caption,
              style: SeenlyText.mono(
                size: 9.5,
                color: claimable ? color : SeenlyPalette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  const _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.4;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, trackPaint);
    if (progress <= 0) return;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
