import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart';

/// A quiet pill with a breathing glow — "N new ›" — for flagging
/// something that genuinely deserves attention (an incoming friend
/// request, a co-viewing circle invite) rather than sitting as a bare
/// "see all" link a person has to notice on their own. Extracted from
/// the original friends-count treatment on the profile screen's
/// friends row (still used there) so every place that needs this exact
/// "you have something waiting" signal looks and behaves identically,
/// instead of each screen growing its own slightly different badge.
///
/// Renders nothing for [count] <= 0 — callers can drop this in
/// unconditionally rather than wrapping every call site in its own
/// `if (count > 0)`.
class NotificationCountPill extends StatelessWidget {
  final int count;
  final String label; // e.g. 'new ›', 'waiting ›'
  final Color? color; // defaults to SeenlyPalette.coral
  final double glowSize;

  const NotificationCountPill({
    super.key,
    required this.count,
    this.label = 'new ›',
    this.color,
    this.glowSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final resolvedColor = color ?? SeenlyPalette.coral;
    return BreathingGlow(
      color: resolvedColor,
      size: glowSize,
      period: const Duration(milliseconds: 3400),
      maxOpacity: 0.28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: resolvedColor, borderRadius: BorderRadius.circular(20)),
        child: Text(
          '$count ${label.tr}',
          style: SeenlyText.mono(size: 10, color: Colors.white, weight: FontWeight.w700),
        ),
      ),
    );
  }
}
