import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart' show PressScale;
import '../theme/clay_kit.dart';

/// "Spend N sincerity points on X?" — one shape shared by every place in
/// the app that spends the currency (see backend/app/sincerity.py's
/// module docstring for the full list: revealing a hidden rating,
/// settling a stale item's debt, staking a recommendation). Learn what
/// spending sincerity looks like once, recognize it everywhere.
class SpendConfirmSheet extends StatelessWidget {
  final String title;
  final String body;
  final int cost;
  final int? balance;
  final String confirmLabel;

  const SpendConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.cost,
    this.balance,
    required this.confirmLabel,
  });

  /// Shows the sheet and resolves to whether the person confirmed —
  /// `false` both on an explicit cancel and on dismissal (tap outside,
  /// swipe down), so callers never need to special-case a null. Pass
  /// [balance] when it's already on hand (no extra round trip just for
  /// this sheet); when it isn't, the sheet skips the "у тебя: N" line
  /// and the pre-emptive "not enough" check, and an actual shortfall
  /// simply surfaces as the API call's own error afterward.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required int cost,
    int? balance,
    String? confirmLabel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SpendConfirmSheet(
        title: title,
        body: body,
        cost: cost,
        balance: balance,
        confirmLabel: confirmLabel ?? 'потратить'.tr,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final notEnough = balance != null && balance! < cost;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.dashedBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(title, style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(body, style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.wb_incandescent_outlined, size: 15, color: SeenlyPalette.mustard),
                const SizedBox(width: 6),
                Text(
                  '−$cost',
                  style: SeenlyText.mono(size: 14, weight: FontWeight.w700, color: SeenlyPalette.mustard),
                ),
                const Spacer(),
                if (balance != null)
                  Text(
                    '${'у тебя'.tr}: $balance',
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (notEnough)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'не хватает очков искренности'.tr,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.coral),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: PressScale(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(color: SeenlyPalette.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'отмена'.tr,
                          style: SeenlyText.mono(size: 13, weight: FontWeight.w600, color: SeenlyPalette.inkMuted),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PressScale(
                      onTap: () => Navigator.of(context).pop(true),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          confirmLabel,
                          style: SeenlyText.mono(size: 13, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
