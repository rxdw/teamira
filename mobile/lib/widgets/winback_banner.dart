import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/premium/premium_screen.dart';
import '../services/app_translations.dart';
import '../services/premium_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'trial_banner.dart' show trialLeftLabel;

/// The "welcome back" strip at the top of Home, for the one moment it is
/// true: a cancelled plan just ran out and the personal comeback discount
/// is open (backend app/subscription.py). Tap opens the paywall with the
/// discount already applied to every price.
///
/// It has no close button on purpose — the offer ends by itself within a
/// week — and renders nothing for everyone else, so it costs the rest of
/// Home no space. The server sends a matching push and the shell opens
/// the paywall once (RootShell._maybeShowWinbackNudge); this is the
/// always-visible, still, never-nagging third leg of that series, the
/// same shape as [TrialBanner].
class WinbackBanner extends StatefulWidget {
  const WinbackBanner({super.key});

  @override
  State<WinbackBanner> createState() => _WinbackBannerState();
}

class _WinbackBannerState extends State<WinbackBanner> {
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
      builder: (_) => const PremiumScreen(triggerSource: 'winback_banner'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumService>();
    final percent = premium.winbackPercent;
    final left = premium.winbackTimeLeft;
    if (percent == null || left == null) return const SizedBox.shrink();

    final onAccent = SeenlyPalette.accentOnAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      child: GestureDetector(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.pink.withOpacity(0.9),
                SeenlyPalette.periwinkle.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: SeenlyPalette.softShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: onAccent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('−$percent%',
                    style: SeenlyText.mono(size: 12, color: onAccent, weight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('welcome back offer'.tr,
                        style: SeenlyText.serif(
                            italic: true,
                            size: 14,
                            weight: FontWeight.w600,
                            color: onAccent)),
                    const SizedBox(height: 2),
                    Text('${'your entries are safe'.tr} · ${trialLeftLabel(left)}',
                        style: SeenlyText.mono(size: 9.5, color: onAccent.withOpacity(0.85))),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 16, color: onAccent),
            ],
          ),
        ),
      ),
    );
  }
}
