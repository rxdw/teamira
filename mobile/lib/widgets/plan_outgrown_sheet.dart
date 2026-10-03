import 'package:flutter/material.dart';

import '../screens/premium/premium_screen.dart';
import '../services/app_translations.dart';
import '../services/premium_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A heads-up shown right before someone who *bought* a shared plan
/// grows their co-viewing circle past what that plan covers — a couple
/// plan covers two people, a family plan four (see
/// PremiumService.circleOutgrowsPlan). Past that, the plan stops
/// covering everyone else in the circle at once, so the person adding a
/// friend would quietly take premium away from the people they pay for.
/// Better to say so before the invite goes out than to let them find
/// out from an angry message.
///
/// Resolves to `true` when the invite should go ahead anyway, `false`
/// when the person backed out or went to look at a bigger plan.
/// Callers use it only when [PremiumService.circleOutgrowsPlan] is true;
/// for everyone else it never appears.
Future<bool> confirmCircleOutgrowsPlan(
  BuildContext context, {
  required PremiumService premium,
}) async {
  // A couple plan has a bigger sibling to move up to; a family plan is
  // already the biggest there is.
  final canUpgrade = premium.planKind == PremiumPlanKind.couple;
  final title = canUpgrade
      ? 'your plan covers two'.tr
      : 'your plan covers four'.tr;
  final message = canUpgrade
      ? 'add a third person and the couple plan stops covering the other one — the family plan covers up to four'.tr
      : 'add another person and the family plan stops covering the others — until someone leaves, only you keep premium'.tr;

  final proceed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
      decoration: BoxDecoration(
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
              child: Icon(Icons.groups_2_outlined, size: 24, color: SeenlyPalette.accent),
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
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              // Both primary actions leave the invite unsent: one goes
              // to the paywall (the person can come back and invite
              // once the bigger plan is in place), the other just stays.
              Navigator.of(sheetContext).pop(false);
              if (canUpgrade) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PremiumScreen(
                      triggerSource: 'circle_outgrew_plan',
                      initialKind: PremiumPlanKind.family,
                    ),
                  ),
                );
              }
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
                  Icon(canUpgrade ? Icons.groups_2_outlined : Icons.check,
                      size: 15, color: SeenlyPalette.accentOnAccent),
                  const SizedBox(width: 8),
                  Text(
                    (canUpgrade ? 'see the family plan' : 'keep the circle as it is').tr,
                    style: SeenlyText.serif(italic: true, color: SeenlyPalette.accentOnAccent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.of(sheetContext).pop(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('add anyway'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
            ),
          ),
        ],
      ),
    ),
  );
  // Swiping the sheet away is a "no".
  return proceed ?? false;
}
