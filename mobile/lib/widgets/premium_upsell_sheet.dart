import 'package:flutter/material.dart';

import '../screens/premium/premium_screen.dart';
import '../services/app_translations.dart';
import '../services/premium_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../theme/clay_kit.dart';

/// The soft "you've hit a free-tier ceiling" moment — shown instead of
/// letting an action through, whenever teamira's own on-device counters
/// (see PremiumService) say the free monthly AI-ask or favorites limit
/// is already spent. Same rounded paper-sheet shape as every other
/// confirm sheet in the app (see SettingsScreen's log-out sheet), just
/// with a soft accent icon instead of a warning tone — this isn't an
/// error, just an invitation.
Future<void> showPremiumUpsellSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  // Which free-tier ceiling actually triggered this sheet — e.g.
  // 'ai_ask_limit', 'favorites_limit', 'lists_limit' (see this
  // function's many call sites for the rest). Threaded through to
  // PremiumScreen's own `triggerSource` purely for analytics — see
  // PremiumScreen.triggerSource's own doc comment.
  String triggerSource = 'upsell_sheet',
  // Plan to have preselected on the paywall it opens, for callers that
  // already know which one fits — growing a circle past two points at
  // the family plan, not the solo one. Null keeps PremiumScreen's own
  // default.
  PremiumPlanKind? initialKind,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: SeenlyPalette.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 24, color: SeenlyPalette.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 17, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 10),
          // A small, once-per-sheet aside rather than a guilt trip —
          // teamira is a small/solo project, and it feels honest to say
          // so here, once, in the one place every premium door in the
          // app already funnels through, instead of repeating it on
          // every screen that has its own upsell copy.
          Text(
            'and the developer would be really glad'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PremiumScreen(
                    triggerSource: triggerSource,
                    initialKind: initialKind,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 15, color: SeenlyPalette.accentOnAccent),
                  const SizedBox(width: 8),
                  Text('open premium'.tr,
                      style: SeenlyText.serif(
                          italic: true, color: SeenlyPalette.accentOnAccent)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.of(sheetContext).pop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('not now'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
            ),
          ),
        ],
      ),
    ),
  );
}
