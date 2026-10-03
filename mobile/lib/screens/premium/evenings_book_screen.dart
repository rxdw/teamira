import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/circle_review_service.dart';
import '../../services/error_text.dart';
import '../../services/evenings_book_pdf_service.dart';
import '../../services/premium_service.dart';
import '../../theme/clay_kit.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../partner/album/album_strings.dart' show at;

/// "The book of your evenings" — the circle's joint reviews and the moments
/// of its room evenings as one keepsake PDF (see
/// services/evenings_book_pdf_service.dart), to save, print or send.
///
/// A premium thing for the *circle*: one member's plan is enough for
/// everybody in it, and the server is the judge of that (a plan on the
/// partner's account counts too, which the device can't always tell). So the
/// button is never greyed out by a local guess — it asks, and a 402 turns
/// into [showEveningsBookPaywall], the same answer every other "this circle
/// needs a plan" surface gives.
///
/// Reached from the card on the co-viewing hub's "мы" tab
/// ([EveningsBookEntryCard]) and from the list of premium perks.
class EveningsBookScreen extends StatefulWidget {
  const EveningsBookScreen({super.key});

  @override
  State<EveningsBookScreen> createState() => _EveningsBookScreenState();
}

class _EveningsBookScreenState extends State<EveningsBookScreen> {
  late final CircleReviewService _service = CircleReviewService(ApiClient.instance);

  bool _busy = false;
  bool _empty = false;
  String? _error;

  Future<void> _make() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _empty = false;
      _error = null;
    });
    try {
      final book = await _service.book();
      if (!mounted) return;
      if (book.isEmpty) {
        setState(() => _empty = true);
        return;
      }
      final bytes = await EveningsBookPdfService.build(book);
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: 'tane-evenings-book.pdf');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 402) {
        await showEveningsBookPaywall(context);
      } else {
        setState(() => _error = describeError(e));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = at(
            'не получилось собрать книгу — попробуйте ещё раз',
            'couldn’t put the book together — please try again',
          ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.inkMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BookCover(showPremiumChip: !isPremium),
                    const SizedBox(height: 24),
                    Text(at('что внутри', 'what goes in it'),
                        style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    _InfoShell(rows: [
                      _InfoRow(
                        icon: Icons.rate_review_outlined,
                        title: at('рецензия каждого из вас', 'a review from each of you'),
                        subtitle: at(
                          'оценка, слова и строка — и как совпали ваши вкусы',
                          'the score, the words and the line — and how your tastes lined up',
                        ),
                      ),
                      _InfoRow(
                        icon: Icons.timeline_rounded,
                        title: at('моменты ваших вечеров', 'the moments of your evenings'),
                        subtitle: at(
                          'где вы вместе смеялись и ахали — в том числе в вечерах до подписки',
                          'where you laughed and gasped together — including evenings before the plan',
                        ),
                      ),
                      _InfoRow(
                        icon: Icons.calendar_month_outlined,
                        title: at('вечера по месяцам', 'evenings month by month'),
                        subtitle: at(
                          'от первого до последнего, с постерами и итогами в цифрах',
                          'first to latest, with posters and your numbers at a glance',
                        ),
                      ),
                      _InfoRow(
                        icon: Icons.ios_share,
                        title: at('ваша книга', 'yours to keep'),
                        subtitle: isPremium
                            ? at('сохраните, распечатайте или отправьте', 'save it, print it, or send it')
                            : at('входит в подписку — одной на всех хватит', 'included with premium — one plan covers all of you'),
                      ),
                    ]),
                    if (_empty) ...[
                      const SizedBox(height: 18),
                      _EmptyNote(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: SeenlyText.serif(size: 12, color: SeenlyPalette.coral)),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              decoration: ClayBoxDecoration(color: SeenlyPalette.paper, boxShadow: SeenlyPalette.softShadow),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: PressScale(
                    onTap: _busy ? null : _make,
                    scaleTo: 0.97,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.accent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      alignment: Alignment.center,
                      child: _busy
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.accentOnAccent),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  at('собираем вашу книгу…', 'putting your book together…'),
                                  style: SeenlyText.serif(
                                      italic: true, size: 15, color: SeenlyPalette.accentOnAccent),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_stories_rounded, size: 16, color: SeenlyPalette.accentOnAccent),
                                const SizedBox(width: 8),
                                Text(
                                  at('собрать нашу книгу', 'make our book'),
                                  style: SeenlyText.serif(
                                      italic: true, size: 15, color: SeenlyPalette.accentOnAccent),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one answer to "the book needs a plan" — the couple plan preselected
/// (one subscription covers everybody in the circle), and the pitch is about
/// what it keeps: the evenings you already have, not a limit you hit.
Future<void> showEveningsBookPaywall(BuildContext context, {String source = 'evenings_book'}) {
  return showPremiumUpsellSheet(
    context,
    triggerSource: source,
    initialKind: PremiumPlanKind.couple,
    icon: Icons.auto_stories_outlined,
    title: at('книга ваших вечеров', 'the book of your evenings'),
    message: at(
      'все ваши рецензии и моменты — в одной красивой книге, которую можно сохранить, '
          'распечатать или подарить. вечера, которые вы уже посмотрели, окажутся в ней тоже',
      'all your reviews and moments in one beautiful book you can save, print or give. '
          'the evenings you’ve already watched go into it too',
    ),
  );
}

/// The cover, in miniature: the app's accent with a foil ring — the same
/// shape as the diary keepsake's preview, so the two read as one family.
class _BookCover extends StatelessWidget {
  final bool showPremiumChip;
  const _BookCover({required this.showPremiumChip});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.accent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 16,
            child: Icon(Icons.auto_awesome, size: 14, color: SeenlyPalette.mustard),
          ),
          Positioned(
            right: 18,
            bottom: 16,
            child: Icon(Icons.auto_awesome, size: 14, color: SeenlyPalette.mustard),
          ),
          if (showPremiumChip)
            Positioned(
              right: 14,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SeenlyPalette.mustard,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'premium',
                  style: SeenlyText.mono(size: 9.5, weight: FontWeight.w700, color: SeenlyPalette.ink),
                ),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: SeenlyPalette.mustard, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.favorite_rounded, size: 18, color: SeenlyPalette.mustard),
                ),
                const SizedBox(height: 14),
                Text(
                  at('книга ваших вечеров', 'the book of your evenings'),
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.accentOnAccent),
                ),
                const SizedBox(height: 6),
                Text(
                  at('рецензии и моменты — на память', 'reviews and moments, to keep'),
                  style: SeenlyText.mono(
                    size: 9.5,
                    color: SeenlyPalette.accentOnAccent.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the circle has no opened review with anything written in it.
/// Not an error — an invitation: the book fills itself as evenings happen.
class _EmptyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SeenlyPalette.mustard.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SeenlyPalette.mustard.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note_rounded, size: 22, color: SeenlyPalette.mustard),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              at(
                'в книге пока пусто. как только вы вместе оставите рецензию на общий вечер — '
                    'она окажется здесь',
                'the book is empty for now. once you’ve left a review of an evening together, '
                    'it will be here',
              ),
              style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoShell extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoShell({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: CozyDivider(height: 1, color: SeenlyPalette.border),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: SeenlyPalette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The card on the co-viewing hub's "мы" tab, next to the album's. Draws for
/// any circle — a pair or a company — and loads nothing: assembling the book
/// is a heavy request that belongs to the screen it opens, and an entry point
/// should never be the thing that errors.
///
/// A free circle sees it too, with the premium chip: it's the pitch. Tapping
/// opens the screen, where the paywall waits behind the button.
class EveningsBookEntryCard extends StatelessWidget {
  const EveningsBookEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    return Entrance(
      delay: const Duration(milliseconds: 120),
      child: PressScale(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EveningsBookScreen())),
        scaleTo: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.mustard.withOpacity(0.18),
                SeenlyPalette.accent.withOpacity(0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.mustard.withOpacity(0.32)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: SeenlyPalette.mustard, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            at('книга ваших вечеров', 'the book of your evenings'),
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'premium',
                              style: SeenlyText.mono(
                                size: 9.5,
                                weight: FontWeight.w700,
                                color: SeenlyPalette.accentOnAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      at('рецензии и моменты — в одной книге на память',
                          'reviews and moments in one book, to keep'),
                      style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
