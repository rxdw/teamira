import 'package:flutter/material.dart';

import '../screens/profile/wrapped_screen.dart';
import '../services/locale_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A quiet, one-line invitation on the final "logged" step of the four
/// log screens (cinema / coach / garden / shuttle) — shown only when the
/// entry was just logged *together* with a partner.
///
/// It's the emotional counterpart to the soft limit meters: instead of
/// asking for anything at a moment of friction, it opens the couple's own
/// Wrapped ([WrappedScreen.isCouple]) right when the two of them have
/// just finished a film and rated it. The deck itself is free; the
/// natural next step inside it — exporting it as a keepsake PDF — is the
/// premium one (see KeepsakeExportScreen, trigger `wrapped_pdf_export`),
/// so nothing here pressures anybody, it just puts the good part of the
/// app in front of the person at the best possible moment.
///
/// Built for the dark "pass" backdrop those screens share (paper-tinted
/// text and hairline border on translucent fill), and deliberately
/// compact — the pass step is a fixed column with flexible spacers, so
/// this must stay a single short row.
class TogetherWrappedTeaser extends StatelessWidget {
  final String partnerName;
  const TogetherWrappedTeaser({super.key, required this.partnerName});

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WrappedScreen(isCouple: true, initialScope: 'all'),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SeenlyPalette.paper.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite_border_rounded, size: 16, color: SeenlyPalette.paper.withOpacity(0.85)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ru
                      ? 'вы с $partnerName досмотрели вместе — ваш итог на двоих'
                      : 'you and $partnerName watched together — see your evenings as a pair',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.serif(
                    italic: true,
                    size: 12,
                    color: SeenlyPalette.paper.withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: SeenlyPalette.paper.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
