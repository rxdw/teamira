import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// Explains, in one place, every way a title can end up "planned
/// together" and what it actually takes to get there — pulled out of
/// CoViewingScreen so the same explanation can also open from Watch
/// Together's own setup screen (see TogetherScreen's help icon), instead
/// of writing a second, slightly-different version of the same steps
/// there.
///
/// Same soft, blurred-backdrop card language as everything else someone
/// taps into around this feature (WatchedPreviewCard, PlannedPreviewCard,
/// the Home co-viewing sheet) — tapping anywhere outside the card closes
/// it, no need to reach for the phone's back gesture/button.
Future<void> showHowItWorksSheet(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'how co-viewing works',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => const HowItWorksSheet(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class HowItWorksSheet extends StatelessWidget {
  const HowItWorksSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: GestureDetector(
                onTap: () {}, // swallow — a tap on the card itself shouldn't dismiss it
                child: Container(
                  width: 320,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('how co-viewing works'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 13, color: SeenlyPalette.inkMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'every way a title ends up planned, and what it takes to get there'.tr,
                        style: SeenlyText.serif(italic: true, size: 11, color: SeenlyPalette.inkMuted),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              _HowItWorksStep(
                                number: '1',
                                title: 'suggest, then they agree',
                                body: 'One tap from a title page sends it to your partner\'s '
                                    'Home card, or the "suggested" tab here. It only lands '
                                    'in "planned" once they accept — ✕ declines it for good.',
                              ),
                              _HowItWorksStep(
                                number: '2',
                                title: 'watch together — one phone',
                                body: 'Passing the phone back and forth, one swipe is already '
                                    'both your yes — no second turn needed. It lands in '
                                    '"planned" the moment you decide.',
                              ),
                              _HowItWorksStep(
                                number: '3',
                                title: 'watch together — over the network',
                                body: 'Each on your own phone with a shared code, swiping '
                                    'blind. Only a title you both separately say yes to '
                                    'becomes a match.',
                              ),
                              _HowItWorksStep(
                                number: '4',
                                title: 'mark it watched',
                                body: 'Either of you can tap "watched" once you\'ve actually '
                                    'seen it — that logs the evening into both your diaries '
                                    'at once.',
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'this shared list is separate from your own "plan to watch" on Profile. Whether a match also lands there is up to you — see "co-viewing" in Settings.'.tr,
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  final bool isLast;

  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: SeenlyPalette.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(number,
                style: SeenlyText.mono(
                    size: 9, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body,
                    style: SeenlyText.serif(size: 11, color: SeenlyPalette.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
