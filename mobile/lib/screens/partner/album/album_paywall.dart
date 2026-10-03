import 'package:flutter/material.dart';

import '../../../services/premium_service.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/premium_upsell_sheet.dart';
import 'album_strings.dart';

/// What the person was trying to do when the album asked for a plan. The
/// copy follows it: someone who has just used up their free notes should be
/// told exactly that, not handed a generic pitch.
enum AlbumPaywallKind {
  /// Nothing specific — the home screen's banner.
  general,

  /// A new note, with the free ones spent.
  notes,

  /// A new capsule, with the free one sealed.
  capsule,

  /// The anniversary date, which has no free allowance.
  anniversary,
}

/// The one answer to "this circle needs a plan for that" — used by every
/// write in this folder, whether the client noticed first (the status says
/// the allowance is spent) or the server did (a 402).
///
/// The framing is the whole point of the feature's pitch: not "you hit a
/// limit" but "this is for the two of you, and it costs less together" —
/// the couple plan is offered pre-selected, and one subscription covers
/// both people (see the seat rules in backend routers/premium.py). For the
/// two capped kinds the sheet also says plainly that what's already written
/// stays — the free allowance is a taste, not a trial that takes things back.
Future<void> showAlbumPaywall(
  BuildContext context, {
  AlbumPaywallKind kind = AlbumPaywallKind.general,
  String source = 'pair_album',
}) {
  final String title;
  final String message;
  final IconData icon;
  switch (kind) {
    case AlbumPaywallKind.notes:
      icon = Icons.mail_outline_rounded;
      title = at('бесплатные записки закончились', 'your free notes are used up');
      message = at(
        'с подпиской на двоих записки можно оставлять без счёта — вдвоём это дешевле. '
            'всё, что вы уже написали, останется с вами',
        'with a plan for two you can leave as many notes as you like — and it costs '
            'less together. everything you\'ve already written stays with you',
      );
      break;
    case AlbumPaywallKind.capsule:
      icon = Icons.lock_clock_rounded;
      title = at('новая капсула — с подпиской', 'the next capsule comes with a plan');
      message = at(
        'первая капсула была в подарок и откроется в срок в любом случае. '
            'чтобы запечатывать новые, нужна подписка на двоих — вдвоём это дешевле',
        'the first capsule was on us and will open on its day either way. to seal '
            'new ones you need a plan for two — and it costs less together',
      );
      break;
    case AlbumPaywallKind.anniversary:
      icon = Icons.favorite_rounded;
      title = at('годовщина — для вас двоих', 'the anniversary — for the two of you');
      message = at(
        'выберите день, с которого всё началось, — и альбом сам покажет, как копятся ваши дни. '
            'одна подписка на двоих, и вдвоём это дешевле',
        'pick the day it all began and the album counts your days for you. one plan '
            'covers both of you — and it costs less together',
      );
      break;
    case AlbumPaywallKind.general:
      icon = Icons.menu_book_rounded;
      title = at('альбом пары — для вас двоих', 'the pair album — for the two of you');
      message = at(
        'записки друг другу без счёта, больше капсул «откроем через год» и ваша годовщина. '
            'одна подписка — на двоих, и вдвоём это дешевле',
        'notes for each other without a limit, more time capsules, and your '
            'anniversary. one subscription covers both of you — and it costs '
            'less together',
      );
      break;
  }
  return showPremiumUpsellSheet(
    context,
    triggerSource: source,
    initialKind: PremiumPlanKind.couple,
    icon: icon,
    title: title,
    message: message,
  );
}

/// A small, quiet line telling a free circle what's left of its allowance —
/// shown inside the compose sheets, in the same soft accent tint as their
/// other notes. Informational only: it never blocks anything and never
/// appears for a circle with a plan.
class FreeAllowanceNote extends StatelessWidget {
  final String text;
  const FreeAllowanceNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.card_giftcard_rounded, size: 16, color: SeenlyPalette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
