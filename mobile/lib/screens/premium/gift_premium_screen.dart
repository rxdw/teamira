import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/premium_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';

/// "подарить подписку" — same shape as [PremiumScreen] but a gift vibe
/// (a gift box instead of the sparkle mark, warmer copy, no couple
/// toggle since a gift is always for one other person) and cheaper
/// prices (see PremiumPricing.gift) than the regular individual plan.
///
/// Written directly in Russian, same reasoning as PremiumScreen's own
/// doc comment.
class GiftPremiumScreen extends StatefulWidget {
  const GiftPremiumScreen({super.key});

  @override
  State<GiftPremiumScreen> createState() => _GiftPremiumScreenState();
}

class _GiftPremiumScreenState extends State<GiftPremiumScreen> {
  PremiumDuration _duration = PremiumDuration.sixMonths;
  bool _sending = false;
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer('TEAMIRA-');
    var seed = now;
    for (var i = 0; i < 6; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buf.write(chars[seed % chars.length]);
    }
    return buf.toString();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    // No gift-delivery backend to hand this off to yet — same "demo
    // stands in for the real checkout" spirit as PremiumService.purchase.
    // What a real flow leaves someone with either way: a redeemable code.
    await Future.delayed(const Duration(milliseconds: 500));
    final code = _generateCode();
    if (!mounted) return;
    setState(() => _sending = false);
    await _showGiftReady(code);
  }

  Future<void> _showGiftReady(String code) {
    final recipient = _nameController.text.trim();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.scale(scale: t, child: child),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: SeenlyPalette.mustard, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(Icons.card_giftcard, size: 28, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              recipient.isEmpty ? 'подарок готов' : 'подарок для $recipient готов',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'отправь этот код — его нужно будет ввести в настройках, чтобы включить премиум',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SeenlyPalette.dashedBorder),
              ),
              alignment: Alignment.center,
              child: Text(code,
                  style: SeenlyText.mono(size: 16, weight: FontWeight.w700, color: SeenlyPalette.ink)),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () {
                final note = _noteController.text.trim();
                final message = [
                  if (recipient.isNotEmpty) 'Для $recipient —',
                  'дарю тебе подписку teamira premium 🎁',
                  if (note.isNotEmpty) '"$note"',
                  'код: $code',
                ].join('\n');
                Share.share(message);
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
                    Icon(Icons.ios_share, size: 15, color: SeenlyPalette.accentOnAccent),
                    const SizedBox(width: 8),
                    Text('поделиться подарком',
                        style: SeenlyText.serif(italic: true, color: SeenlyPalette.accentOnAccent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('готово',
                    textAlign: TextAlign.center,
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = PremiumPricing.gift[_duration]!;
    final save = PremiumPricing.giftSavePercent(_duration);

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
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _GiftHero(),
                    const SizedBox(height: 26),
                    Text('кому дарим?', style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    _SoftField(
                      controller: _nameController,
                      hint: 'имя (необязательно)',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 10),
                    _SoftField(
                      controller: _noteController,
                      hint: 'тёплые слова к подарку (необязательно)',
                      icon: Icons.edit_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    Text('на сколько подарим премиум?',
                        style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    _GiftDurationList(
                      selected: _duration,
                      onChanged: (d) => setState(() => _duration = d),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.mustard.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.favorite_outline, size: 16, color: SeenlyPalette.clay),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'подарок дешевле обычной подписки — это подарок, а не покупка для себя',
                              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              decoration: BoxDecoration(color: SeenlyPalette.paper, boxShadow: SeenlyPalette.softShadow),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: PressScale(
                        onTap: _send,
                        scaleTo: 0.97,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.mustard,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: _sending
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.accentOnAccent),
                                  ),
                                )
                              : Text('подарить за $price ₽',
                                  style: SeenlyText.serif(
                                      italic: true, size: 15, color: SeenlyPalette.accentOnAccent)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      save > 0 ? 'на $save% дешевле обычной подписки на тот же срок' : 'разовый платёж, без автопродления',
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftHero extends StatelessWidget {
  const _GiftHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SeenlyPalette.mustard.withOpacity(0.9),
            SeenlyPalette.coral.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: SeenlyPalette.accentOnAccent.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.card_giftcard, size: 21, color: SeenlyPalette.accentOnAccent),
          ),
          const SizedBox(height: 16),
          Text('подарить премиум',
              style: SeenlyText.serif(
                  italic: true, size: 22, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
          const SizedBox(height: 6),
          Text(
            'подари уютные вечера без ограничений — своим, партнёру, другу',
            style: SeenlyText.serif(size: 13, color: SeenlyPalette.accentOnAccent.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }
}

class _SoftField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  const _SoftField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 12 : 0),
            child: Icon(icon, size: 16, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: SeenlyText.serif(size: 13.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                hintText: hint,
                hintStyle: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftDurationList extends StatelessWidget {
  final PremiumDuration selected;
  final ValueChanged<PremiumDuration> onChanged;
  const _GiftDurationList({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PremiumDuration.values.map((d) {
        final price = PremiumPricing.gift[d]!;
        final isSelected = selected == d;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: d != PremiumDuration.year ? 8 : 0),
            child: GestureDetector(
              onTap: () => onChanged(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? SeenlyPalette.mustard.withOpacity(0.16) : SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? SeenlyPalette.clay : SeenlyPalette.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      switch (d) {
                        PremiumDuration.month => 'месяц',
                        PremiumDuration.sixMonths => 'полгода',
                        PremiumDuration.year => 'год',
                      },
                      style: SeenlyText.serif(
                          size: 13, weight: FontWeight.w600, color: SeenlyPalette.ink),
                    ),
                    const SizedBox(height: 4),
                    Text('$price ₽',
                        style: SeenlyText.mono(
                            size: 10.5, weight: FontWeight.w700, color: SeenlyPalette.clay)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
