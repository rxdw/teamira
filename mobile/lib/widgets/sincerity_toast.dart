import 'package:flutter/material.dart';

import '../models/sincerity.dart';
import '../services/app_translations.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// Call right after any action that might return sincerity_awarded
/// (currently DiaryEntry.sincerityAwarded — see that field's own
/// docstring) with the list from that response. Shows nothing if the
/// list is empty, so every call site can call this unconditionally
/// after a save rather than checking isNotEmpty itself.
///
/// Deliberately a plain SnackBar, not a celebratory animation or sound
/// — see the product note behind the whole feature: this is a quiet
/// mirror, not a reward ping. One SnackBar per transaction, shown back
/// to back if there's more than one (e.g. closing a stale gestalt AND
/// revising the rating in the same save) rather than merged into a
/// single line — each is its own small, separately-true statement.
void showSincerityToasts(BuildContext context, List<SincerityTransaction> awards) {
  if (awards.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  for (final award in awards) {
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SeenlyPalette.paper,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(Icons.wb_incandescent_outlined, size: 18, color: SeenlyPalette.mustard),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                award.delta > 0
                    // .tr on a string that's already had the delta
                    // spliced in can never match anything in
                    // AppTranslations — the text is different every
                    // time. Translating _reasonLine's fixed phrase
                    // first, then splicing the number in around the
                    // already-translated result, is what actually
                    // works; see tools/l10n/check_missing_translations.py,
                    // which is how this got caught.
                    ? '+${award.delta} · ${_reasonLine(award.reason).tr}'
                    : _reasonLine(award.reason).tr,
                style: SeenlyText.serif(size: 13, color: SeenlyPalette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonLine(String reason) {
  switch (reason) {
    case 'closed_gestalt':
      return 'закрыл(а) давнее ожидание';
    case 'revised_rating':
      return 'изменил(а) старую оценку';
    case 'honest_drop':
      return 'честно бросил(а) с причиной';
    default:
      return reason;
  }
}
