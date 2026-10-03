import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../theme/notebook_paper.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../theme/clay_kit.dart';

/// A small "used X of Y" progress strip for a free-tier ceiling — shown
/// inline, ahead of time, in the screen that actually counts toward it
/// (favorite films, custom lists), rather than only ever appearing the
/// moment [PremiumService.canAddFavorite]/[canAddList] finally says no
/// and [showPremiumUpsellSheet] pops up instead (see that widget's own
/// doc comment — this is the *other*, earlier soft-paywall shape).
///
/// The idea: seeing "4 of 5" while there's still one slot left builds
/// willingness to upgrade ahead of the actual wall, instead of only
/// ever asking at the exact moment of a hard no. Free accounts only —
/// premium has nothing to warn about, so callers should simply not
/// build this widget at all when [PremiumService.isPremium] is true
/// (kept as the caller's job, same as every other premium check in
/// this app, rather than this widget silently no-op'ing on a flag it
/// would otherwise need threaded in just to immediately ignore).
///
/// [used]/[limit] drive the bar; [label] is the already-localized
/// "4 of 5 favorite films" line (composed at the call site the same
/// way the rest of the app builds a number + noun phrase — see
/// services/home_widget_service.dart's `'$watched из $total просмотрено'`
/// for the established pattern — since the noun's Russian form here
/// never actually changes with [used] itself: only the fixed [limit]
/// decides the noun's case, and that's a compile-time constant per
/// screen, not something that needs full ICU plural handling).
class SoftLimitMeter extends StatelessWidget {
  final int used;
  final int limit;
  final String label;
  final VoidCallback onTapUpgrade;

  const SoftLimitMeter({
    super.key,
    required this.used,
    required this.limit,
    required this.label,
    required this.onTapUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = used.clamp(0, limit);
    final ratio = limit <= 0 ? 0.0 : clamped / limit;
    // Warms from the accent to mustard as the ceiling gets close, so
    // the bar itself reads as "still fine" → "worth thinking about"
    // without ever needing an alarming red — this is an invitation,
    // not an error state.
    final atLimit = clamped >= limit;
    final barColor = atLimit ? SeenlyPalette.mustard : SeenlyPalette.accent;

    return GestureDetector(
      onTap: onTapUpgrade,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.auto_awesome, size: 12, color: SeenlyPalette.accent),
                const SizedBox(width: 3),
                Text(
                  'premium'.tr,
                  style: SeenlyText.mono(
                    size: 10,
                    weight: FontWeight.w700,
                    color: SeenlyPalette.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: RuledProgressBar(
                value: ratio,
                minHeight: 5,
                backgroundColor: SeenlyPalette.border,
                valueColor: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
