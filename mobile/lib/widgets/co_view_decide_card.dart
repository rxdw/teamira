import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../screens/partner/co_view_decide_method_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'co_view_pick_sheets.dart';
import '../services/app_translations.dart';

/// A quiet way in to "decide together" — ask teamira, let a dice or the
/// reel pick, or vote through what you've each got queued, and have the
/// whole circle weigh in on wherever any of those methods land rather
/// than one phone just adding it. Same dashed, low-pressure card
/// language as [EveningPlanCard]'s own empty state, so it reads as an
/// invitation sitting next to it rather than a second, competing
/// feature. [onChanged] fires once something actually lands on the
/// shared planned list, so the caller can refresh.
class CoViewDecideCard extends StatelessWidget {
  final VoidCallback? onChanged;
  const CoViewDecideCard({super.key, this.onChanged});

  Future<void> _openMethods(BuildContext context) async {
    final winner = await Navigator.of(context).push<MediaItem?>(
      MaterialPageRoute(builder: (_) => const CoViewDecideMethodScreen()),
    );
    if (winner != null) onChanged?.call();
  }

  Future<void> _openRandom(BuildContext context) async {
    final winner = await showCoViewRandomPickSheet(context);
    if (winner != null) onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.how_to_vote_outlined, size: 20, color: SeenlyPalette.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openMethods(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("can't decide?".tr, style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    "ask teamira, vote, or let a dice pick".tr,
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 30, color: SeenlyPalette.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          IconButton(
            tooltip: 'pick for us'.tr,
            onPressed: () => _openRandom(context),
            icon: Icon(Icons.casino_outlined, size: 19, color: SeenlyPalette.accent),
          ),
        ],
      ),
    );
  }
}
