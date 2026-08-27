import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/premium_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import 'gift_premium_screen.dart';

/// The "оформление премиум подписки" screen — reached from the Premium
/// banner on Profile, the lock on the shuttle log theme in Settings, and
/// every free-tier upsell sheet (see widgets/premium_upsell_sheet.dart).
///
/// Written directly in Russian rather than wired through `.tr` — same
/// choice already made for screens/profile/wrapped_screen.dart (see
/// AppTranslations' own docstring on that "known gap"): this is a
/// self-contained feature screen with rouble pricing baked in either
/// way, so a parallel English copy would never actually get shown.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumPlanKind _kind = PremiumPlanKind.individual;
  PremiumDuration _duration = PremiumDuration.year;
  bool _purchasing = false;

  Future<void> _purchase() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    final premium = context.read<PremiumService>();
    await premium.purchase(_kind, _duration);
    if (!mounted) return;
    setState(() => _purchasing = false);
    await _showSuccess();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showSuccess() {
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
                  decoration: BoxDecoration(
                    color: SeenlyPalette.accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.auto_awesome, size: 28, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('премиум подключён',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _kind == PremiumPlanKind.couple
                  ? 'теперь у вас двоих безлимит на всё — приятного просмотра вместе'
                  : 'теперь у тебя безлимит на всё — приятного просмотра',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(sheetContext).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text('здорово',
                    style: SeenlyText.serif(italic: true, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumService>();
    final price = PremiumPricing.priceFor(_kind, _duration);
    final perMonth = PremiumPricing.perMonth(_kind, _duration);

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
                    icon: Icon(Icons.close, size: 20, color: SeenlyPalette.inkMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (premium.isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.sage.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('уже с тобой',
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.sage)),
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
                    _Hero(kind: _kind),
                    const SizedBox(height: 26),
                    Text('на кого оформляем?',
                        style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    _KindToggle(
                      kind: _kind,
                      onChanged: (k) => setState(() => _kind = k),
                    ),
                    const SizedBox(height: 24),
                    Text('на сколько?', style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    _DurationList(
                      kind: _kind,
                      selected: _duration,
                      onChanged: (d) => setState(() => _duration = d),
                    ),
                    const SizedBox(height: 26),
                    Text('что входит', style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    const _FeatureCard(),
                    const SizedBox(height: 22),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const GiftPremiumScreen()),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.card_giftcard_outlined,
                                size: 14, color: SeenlyPalette.accent),
                            const SizedBox(width: 6),
                            Text('подарить подписку близкому человеку',
                                style: SeenlyText.serif(
                                    italic: true, size: 12.5, color: SeenlyPalette.accent)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.paper,
                boxShadow: SeenlyPalette.softShadow,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: PressScale(
                        onTap: premium.isPremium ? () {} : _purchase,
                        scaleTo: 0.97,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: premium.isPremium
                                ? SeenlyPalette.inkFaint
                                : SeenlyPalette.accent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: _purchasing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.accentOnAccent),
                                  ),
                                )
                              : Text(
                                  premium.isPremium
                                      ? 'премиум уже подключён'
                                      : 'оформить за $price ₽',
                                  style: SeenlyText.serif(
                                      italic: true,
                                      size: 15,
                                      color: SeenlyPalette.accentOnAccent),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _duration == PremiumDuration.month
                          ? 'далее $perMonth ₽ в месяц · можно отменить в любой момент'
                          : '≈ $perMonth ₽/мес · оплата один раз за весь срок',
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

class _Hero extends StatelessWidget {
  final PremiumPlanKind kind;
  const _Hero({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SeenlyPalette.accent.withOpacity(0.94),
            SeenlyPalette.accent,
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
              color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.auto_awesome, size: 21, color: SeenlyPalette.accentOnAccent),
          ),
          const SizedBox(height: 16),
          Text('teamira премиум',
              style: SeenlyText.serif(
                  italic: true, size: 22, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
          const SizedBox(height: 6),
          Text(
            kind == PremiumPlanKind.couple
                ? 'один уютный вечер на двоих — без ограничений для обоих'
                : 'чуть больше пространства для твоих вечеров',
            style: SeenlyText.serif(size: 13, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }
}

class _KindToggle extends StatelessWidget {
  final PremiumPlanKind kind;
  final ValueChanged<PremiumPlanKind> onChanged;
  const _KindToggle({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KindCard(
            icon: Icons.person_outline,
            title: 'на одного',
            subtitle: 'только для тебя',
            selected: kind == PremiumPlanKind.individual,
            onTap: () => onChanged(PremiumPlanKind.individual),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KindCard(
            icon: Icons.favorite_outline,
            title: 'на пару',
            subtitle: 'выгоднее вдвоём',
            badge: 'выгоднее',
            selected: kind == PremiumPlanKind.couple,
            onTap: () => onChanged(PremiumPlanKind.couple),
          ),
        ),
      ],
    );
  }
}

class _KindCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            decoration: BoxDecoration(
              color: selected ? SeenlyPalette.accent.withOpacity(0.1) : SeenlyPalette.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 19, color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
                    if (selected)
                      Icon(Icons.check_circle, size: 17, color: SeenlyPalette.accent),
                  ],
                ),
                const SizedBox(height: 10),
                Text(title,
                    style: SeenlyText.serif(
                        size: 14.5, weight: FontWeight.w600, color: SeenlyPalette.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: -8,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SeenlyPalette.coral,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge!,
                    style: SeenlyText.mono(
                        size: 8.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DurationList extends StatelessWidget {
  final PremiumPlanKind kind;
  final PremiumDuration selected;
  final ValueChanged<PremiumDuration> onChanged;
  const _DurationList({required this.kind, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: PremiumDuration.values.map((d) {
        final price = PremiumPricing.priceFor(kind, d);
        final perMonth = PremiumPricing.perMonth(kind, d);
        final save = PremiumPricing.savePercent(kind, d);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _DurationRow(
            label: switch (d) {
              PremiumDuration.month => 'месяц',
              PremiumDuration.sixMonths => 'полгода',
              PremiumDuration.year => 'год',
            },
            perPersonNote: kind == PremiumPlanKind.couple
                ? '≈ ${PremiumPricing.perPersonPerMonth(d)} ₽/мес с человека'
                : null,
            price: price,
            perMonth: perMonth,
            savePercent: save,
            selected: selected == d,
            onTap: () => onChanged(d),
          ),
        );
      }).toList(),
    );
  }
}

class _DurationRow extends StatelessWidget {
  final String label;
  final String? perPersonNote;
  final int price;
  final int perMonth;
  final int savePercent;
  final bool selected;
  final VoidCallback onTap;
  const _DurationRow({
    required this.label,
    this.perPersonNote,
    required this.price,
    required this.perMonth,
    required this.savePercent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.1) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SeenlyPalette.accent : SeenlyPalette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: SeenlyText.serif(
                              size: 14, weight: FontWeight.w600, color: SeenlyPalette.ink)),
                      if (savePercent > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.sage.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text('-$savePercent%',
                              style: SeenlyText.mono(
                                  size: 9, weight: FontWeight.w700, color: SeenlyPalette.sage)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perPersonNote ?? '≈ $perMonth ₽/мес',
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            Text('$price ₽',
                style: SeenlyText.serif(
                    size: 15, weight: FontWeight.w600, color: SeenlyPalette.ink)),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        children: const [
          _FeatureRow(
            icon: Icons.auto_awesome_outlined,
            title: 'безлимитные вопросы teamira',
            subtitle: 'на бесплатном — 3 в месяц',
          ),
          _FeatureDivider(),
          _FeatureRow(
            icon: Icons.favorite_outline,
            title: 'сколько угодно избранных фильмов',
            subtitle: 'на бесплатном — до 5',
          ),
          _FeatureDivider(),
          _FeatureRow(
            icon: Icons.rocket_launch_outlined,
            title: 'тема оформления «космический шаттл»',
            subtitle: 'эксклюзивно для премиума',
          ),
        ],
      ),
    );
  }
}

class _FeatureDivider extends StatelessWidget {
  const _FeatureDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Divider(height: 1, color: SeenlyPalette.border),
      );
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

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
                Text(title,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.ink)),
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
