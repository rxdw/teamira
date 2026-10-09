import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart';
import '../services/locale_service.dart';

/// Maps a backend `icon_key` onto this app's icon set. Unknown keys fall
/// back to a neutral star rather than throwing, so the backend can add a
/// challenge with a new icon without needing an app release to go with it.
IconData challengeIcon(String key) {
  switch (key) {
    case 'calendar':
      return Icons.event_note_outlined;
    case 'palette':
      return Icons.palette_outlined;
    case 'clock':
      return Icons.schedule_rounded;
    case 'heart':
      return Icons.favorite_border_rounded;
    case 'pen':
      return Icons.edit_note_rounded;
    case 'film':
      return Icons.local_movies_outlined;
    case 'users':
      return Icons.people_alt_outlined;
    case 'shuffle':
      return Icons.shuffle_rounded;
    case 'globe':
      return Icons.public_rounded;
    default:
      return Icons.star_border_rounded;
  }
}

/// A soft, hand-drawn-looking progress bar — rounded, low-contrast, with
/// the filled part in the accent and the track a barely-there tint of it.
/// Deliberately not a LinearProgressIndicator: that reads as a loading
/// bar (system-y, busy), and this is a keepsake, not a download.
class SoftProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final double height;

  const SoftProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? SeenlyPalette.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: tint.withOpacity(0.13)),
          // Animated rather than instant so a challenge that ticks up
          // while the screen is open visibly *fills* rather than jumping —
          // the small bit of motion is most of what makes progress feel
          // like something happened.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v == 0 ? 0.0001 : v,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One challenge, as a paper card.
///
/// Three visual states, and they're genuinely different rather than the
/// same card with a tint:
///   - in progress — progress bar, "осталось N", days left
///   - finished, uncollected — warm mustard edge and a "забрать" button,
///     because there's something to do
///   - collected — quiet, faded, a small check; done is done and it
///     shouldn't keep competing for attention
class ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final VoidCallback? onClaim;
  final VoidCallback? onTap;
  final bool claiming;
  final bool compact;

  const ChallengeCard({
    super.key,
    required this.challenge,
    this.onClaim,
    this.onTap,
    this.claiming = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final claimable = c.claimable;
    final done = c.completed;

    final accent = claimable
        ? SeenlyPalette.mustard
        : (c.isWeekly ? SeenlyPalette.sage : SeenlyPalette.accent);

    return PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(compact ? 13 : 16),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: claimable ? accent.withOpacity(0.55) : SeenlyPalette.border,
            width: claimable ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: SeenlyPalette.shadowColor.withOpacity(claimable ? 0.10 : 0.05),
              blurRadius: claimable ? 16 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Opacity(
          // Collected challenges stay readable but stop shouting.
          opacity: (done && !claimable) ? 0.62 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      done && !claimable ? Icons.check_rounded : challengeIcon(c.iconKey),
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title, style: SeenlyText.cardTitle),
                        const SizedBox(height: 2),
                        Text(
                          c.caption,
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    _PointsTag(points: c.points, accent: accent, dimmed: done && !claimable),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SoftProgressBar(
                      value: c.progress,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${c.current}/${c.target}',
                    style: SeenlyText.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: done ? accent : SeenlyPalette.inkFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(child: _FootNote(challenge: c)),
                  if (claimable)
                    _ClaimButton(
                      accent: accent,
                      loading: claiming,
                      onTap: onClaim,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsTag extends StatelessWidget {
  final int points;
  final Color accent;
  final bool dimmed;
  const _PointsTag({required this.points, required this.accent, this.dimmed = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withOpacity(dimmed ? 0.08 : 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '+$points',
          style: SeenlyText.mono(size: 10, weight: FontWeight.w700, color: accent),
        ),
      );
}

/// The quiet line under the bar. Says the single most useful thing for
/// whichever state the challenge is in, rather than stacking three
/// possible captions on top of each other.
class _FootNote extends StatelessWidget {
  final Challenge challenge;
  const _FootNote({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    // These lines splice numbers into a sentence, so word order differs by
    // language and `.tr` on the finished string could never match — each
    // language gets its own sentence instead.
    final ru = LocaleService.appIsRussian;
    String text;
    if (c.claimable) {
      text = ru ? 'готово — забери награду' : 'ready — claim your reward';
    } else if (c.completed) {
      text = ru ? 'выполнено' : 'done';
    } else if (c.isWeekly) {
      final d = c.daysLeft ?? 0;
      final left = d <= 0
          ? (ru ? 'последний день' : 'last day')
          : (d == 1
              ? (ru ? 'остался день' : '1 day left')
              : (ru ? 'осталось $d ${nOnly('nDays', d)}' : '$d ${nOnly('nDays', d)} left'));
      text = ru ? 'ещё ${c.remaining} · $left' : '${c.remaining} to go · $left';
    } else {
      text = ru ? 'ещё ${c.remaining} до конца года' : '${c.remaining} to go this year';
    }
    return Text(
      text,
      style: SeenlyText.mono(
        size: 10.5,
        color: c.claimable ? SeenlyPalette.mustard : SeenlyPalette.inkFaint,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ClaimButton extends StatelessWidget {
  final Color accent;
  final bool loading;
  final VoidCallback? onTap;
  const _ClaimButton({required this.accent, this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        haptics: true,
        onTap: loading ? null : onTap,
        scaleTo: 0.93,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: loading
              ? SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.paperOnDark),
                  ),
                )
              : Text(
                  'забрать'.tr,
                  style: SeenlyText.serif(
                    size: 13,
                    italic: true,
                    weight: FontWeight.w600,
                    color: SeenlyPalette.paperOnDark,
                  ),
                ),
        ),
      );
}
