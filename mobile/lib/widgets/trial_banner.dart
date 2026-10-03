import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/premium/premium_screen.dart';
import '../services/app_translations.dart';
import '../services/premium_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../theme/clay_kit.dart';

/// "5 h left" / "2 d left" / "less than an hour left" — the one wording
/// for a free period's remaining time, shared by this banner and the
/// paywall's hero chip so the two can never disagree.
String trialLeftLabel(Duration left) {
  if (left < const Duration(hours: 1)) return 'less than an hour left'.tr;
  if (left < const Duration(hours: 24)) return '${left.inHours} ${'h left'.tr}';
  return '${left.inDays} ${'d left'.tr}';
}

/// A quiet strip at the top of Home about the free period, in the two
/// moments it matters and nowhere else:
///   - the last 48 hours of it — a live countdown, tap opens the paywall;
///   - after it ended — one "bring unlimited back" strip with a close
///     button that stays closed (per account) once dismissed.
/// Renders nothing for everyone else (never trialed, plenty of time
/// left, or already an owner), so it costs the rest of Home no space.
///
/// The server sends matching pushes (backend app/trial.py) and the shell
/// opens the paywall once per stage (RootShell._maybeShowTrialNudge);
/// this is the always-visible, never-nagging third leg of the same
/// series — it never blocks anything and it sits still.
class TrialBanner extends StatefulWidget {
  const TrialBanner({super.key});

  @override
  State<TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends State<TrialBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Minute granularity is plenty: the label switches at whole hours.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _open() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const PremiumScreen(triggerSource: 'trial_banner'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumService>();
    if (premium.ownsPlan) return const SizedBox.shrink();

    final String title;
    final String subtitle;
    final bool closable;
    if (premium.trialExpired) {
      if (premium.expiredBannerDismissed) return const SizedBox.shrink();
      title = 'your free period has ended'.tr;
      subtitle = 'bring unlimited back whenever you like'.tr;
      closable = true;
    } else {
      final left = premium.trialTimeLeft;
      if (left == null || left > const Duration(hours: 48)) return const SizedBox.shrink();
      title = '${'free period'.tr}: ${trialLeftLabel(left)}';
      subtitle = 'keep everything unlimited'.tr;
      closable = false;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: GestureDetector(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: ClayBoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.mustard.withOpacity(0.85),
                SeenlyPalette.coral.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: SeenlyPalette.softShadow,
          ),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_outlined, size: 18, color: SeenlyPalette.accentOnAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: SeenlyText.serif(
                            italic: true,
                            size: 14,
                            weight: FontWeight.w600,
                            color: SeenlyPalette.accentOnAccent)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: SeenlyText.mono(
                            size: 9.5, color: SeenlyPalette.accentOnAccent.withOpacity(0.85))),
                  ],
                ),
              ),
              if (closable)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: SeenlyPalette.accentOnAccent),
                  onPressed: () => context.read<PremiumService>().dismissExpiredBanner(),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: SeenlyPalette.accentOnAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
