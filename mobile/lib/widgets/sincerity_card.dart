import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/profile/sincerity_screen.dart';
import '../services/app_translations.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../theme/clay_kit.dart';

/// The profile screen's entry point into the whole sincerity-points
/// feature (see backend/app/sincerity.py's module docstring for the
/// product reasoning). Deliberately quiet: a plain number and one soft
/// line, no badge-y shine, no red dot, nothing implying it needs
/// attention — this is a mirror, not a notification. Sits right after
/// the stats grid card in profile_screen.dart's build method.
///
/// Fetches its own balance on mount rather than taking one as a
/// constructor argument — keeps it fully decoupled from
/// ProfileScreen's existing data-loading pipeline (ProfileStats etc.),
/// so dropping this card in never risks touching that unrelated code
/// path. Renders nothing while loading or on error: this card is a
/// bonus, not something worth showing a spinner or error banner for.
class SincerityCard extends StatefulWidget {
  const SincerityCard({super.key});

  @override
  State<SincerityCard> createState() => _SincerityCardState();
}

class _SincerityCardState extends State<SincerityCard> {
  int? _balance;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().sincerity.me().then((b) {
      if (mounted) setState(() => _balance = b.balance);
    }).catchError((_) {
      // Silent — see class doc: this card just doesn't appear rather
      // than show an error for something this low-stakes.
    });
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balance;
    if (balance == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SincerityScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ClayBoxDecoration(
              color: SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(18),
              boxShadow: SeenlyPalette.softShadow,
              border: Border.all(
                color: SeenlyPalette.mustard.withOpacity(isDark ? 0.22 : 0.16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.mustard.withOpacity(isDark ? 0.18 : 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wb_incandescent_outlined,
                    size: 20,
                    color: SeenlyPalette.mustard,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nCount('nSincerityPoints', balance),
                        style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'тихая запись о честности с собой'.tr,
                        style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
