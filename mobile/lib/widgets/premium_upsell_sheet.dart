import 'package:flutter/material.dart';

import '../screens/premium/premium_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

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
}) {
  return showModalBottomSheet(
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
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
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
                  Text('открыть премиум',
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
              child: Text('не сейчас',
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
            ),
          ),
        ],
      ),
    ),
  );
}
