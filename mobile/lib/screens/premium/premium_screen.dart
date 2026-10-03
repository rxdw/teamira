import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../analytics/analytics.dart';
import '../../services/app_translations.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../services/premium_service.dart';
import 'manage_subscription_screen.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/trial_banner.dart' show trialLeftLabel;
import '../../widgets/wow_motion.dart';
import '../legal/eula_screen.dart';
import '../legal/privacy_policy_screen.dart';
import 'gift_premium_screen.dart';
import '../../theme/clay_kit.dart';
import '../partner/album/album_strings.dart' show at;

/// The subscription paywall — reached from the Premium banner on
/// Profile, the lock on the shuttle log theme in Settings, every
/// free-tier upsell sheet (see widgets/premium_upsell_sheet.dart), the
/// two soft, quietly-shown-ahead-of-a-limit meters on Favorites and
/// Lists (see widgets/soft_limit_meter.dart), and twice, softly and
/// automatically rather than from a tap: once right after onboarding
/// finishes, and once right after two accounts freshly link into a
/// co-viewing couple (see screens/shell/root_shell.dart::
/// _maybeShowOnboardingPaywall and ::_maybeShowPartnerLinkedPaywall).
/// English source strings wired through `.tr`, same as most of the app —
/// see AppTranslations.ru for the Russian copy.
class PremiumScreen extends StatefulWidget {
  /// Where this screen was opened from — purely descriptive (analytics
  /// + the onboarding entry's slightly warmer hero copy below), never
  /// changes what's actually for sale. 'manual' covers every ordinary
  /// entry point (the Profile banner, Settings) that isn't worth telling
  /// apart from one another.
  final String triggerSource;

  /// Plan to have selected when the screen opens, for entry points that
  /// already know which one fits (growing a circle past two → family).
  /// Wins over the default implied by [triggerSource]; the person can
  /// still switch.
  final PremiumPlanKind? initialKind;

  const PremiumScreen({super.key, this.triggerSource = 'manual', this.initialKind});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  // Couple pre-selected only when arriving fresh off linking a partner
  // (see PremiumScreen.triggerSource == 'partner_linked') — the whole
  // point of that soft trigger is to catch the moment right after two
  // accounts pair up, so the plan already on screen should be the one
  // that actually fits what they just did, not the default solo one
  // they'd have to notice and switch away from themselves.
  late PremiumPlanKind _kind = widget.initialKind ??
      (widget.triggerSource == 'partner_linked'
          ? PremiumPlanKind.couple
          : PremiumPlanKind.individual);
  PremiumDuration _duration = PremiumDuration.year;
  bool _purchasing = false;
  bool _startingTrial = false;
  bool _restoring = false;
  bool _showPromoField = false;
  final _promoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Which of the app's many paywall triggers actually led here — see
    // docs/analytics.md. Every other screen gets this for free from the
    // route observer; this one custom event rides alongside that,
    // rather than replacing it, purely to carry the `trigger` value the
    // generic screen-view event has no field for.
    Analytics.instance.track('paywall_shown', {'trigger': widget.triggerSource});
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _purchase() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    final premium = context.read<PremiumService>();
    int? appliedDiscount;
    try {
      appliedDiscount = await premium.purchase(_kind, _duration, promoCode: _promoController.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _purchasing = false);
    await _showSuccess(appliedDiscountPercent: appliedDiscount);
    if (mounted) Navigator.of(context).pop();
  }

  /// The paywall's other call-to-action, offered instead of [_purchase]
  /// whenever `premium.trialAvailable` — see PremiumService.startTrial's
  /// own doc comment for what actually happens server-side. No promo
  /// code, no plan choice: a trial is the same free taste of premium
  /// regardless of which plan someone was looking at when they tapped
  /// it, so `_kind`/`_duration` (still visible on screen) are left
  /// exactly as they were, purely as a preview of what they'd move on
  /// to once the trial itself runs out.
  Future<void> _startTrial() async {
    if (_startingTrial) return;
    setState(() => _startingTrial = true);
    final premium = context.read<PremiumService>();
    try {
      await premium.startTrial();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _startingTrial = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _startingTrial = false);
    await _showSuccess(trial: true);
    if (mounted) Navigator.of(context).pop();
  }

  /// Re-syncs this account's premium state from the server — see
  /// PremiumService.restorePurchases's own doc comment on why that's a
  /// slightly different request than the one [PremiumService.reloadForUser]
  /// makes on every ordinary app launch. The one legal/App-Store-required
  /// control on this whole screen that doesn't lead to a purchase or a
  /// trial, so it gets its own quiet SnackBar rather than the full
  /// success sheet — restoring premium you already own isn't a moment
  /// worth celebrating the way buying it is.
  Future<void> _restorePurchases() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final premium = context.read<PremiumService>();
    final wasPremium = premium.isPremium;
    try {
      await premium.restorePurchases();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('couldn\'t check right now — try again in a moment'.tr)),
        );
      }
      if (mounted) setState(() => _restoring = false);
      return;
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          premium.isPremium
              ? (wasPremium ? 'you\'re already all set'.tr : 'premium restored'.tr)
              : 'nothing to restore on this account'.tr,
        ),
      ),
    );
  }

  Future<void> _showSuccess({int? appliedDiscountPercent, bool trial = false}) {
    final premium = context.read<PremiumService>();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: ClayBoxDecoration(
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
                  child: Icon(trial ? Icons.hourglass_top_outlined : Icons.auto_awesome,
                      size: 28, color: SeenlyPalette.accentOnAccent),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(trial ? 'your free trial has started'.tr : 'premium is on'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              trial
                  ? '${premium.trialDays} ${'days · no card needed · cancel anytime'.tr}'
                  : switch (_kind) {
                      PremiumPlanKind.couple =>
                        'you\'re both unlimited now — enjoy watching together'.tr,
                      PremiumPlanKind.family =>
                        'your whole circle is unlimited now — enjoy watching together'.tr,
                      PremiumPlanKind.individual =>
                        'you\'re unlimited now — enjoy the evenings'.tr,
                    },
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
            ),
            if (appliedDiscountPercent != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: SeenlyPalette.sage.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  // Discount only ever comes from a promo code now —
                  // see backend/app/routers/premium.py::purchase, which
                  // no longer has a standing-discount branch to also
                  // land here (removed along with the old influencer
                  // tiers — see routers/referrals.py::MILESTONES).
                  '${(premium.lastDiscountKind == 'winback' ? 'welcome back offer applied' : 'promo code applied').tr}: −$appliedDiscountPercent%',
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.sage),
                ),
              ),
            ],
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
                child: Text('great'.tr,
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
    // The personal comeback discount (backend app/subscription.py), when
    // one is open: every price on this screen is shown after it, and the
    // server applies the same percent on purchase — see winbackPercent.
    final winback = premium.winbackPercent;
    final basePrice = PremiumPricing.priceFor(_kind, _duration);
    final basePerMonth = PremiumPricing.perMonth(_kind, _duration);
    final price = winback == null ? basePrice : PremiumPricing.discounted(basePrice, winback);
    final perMonth = winback == null ? basePerMonth : PremiumPricing.discounted(basePerMonth, winback);
    final offerTrial = premium.trialAvailable;
    // During a free period isPremium is true (features are unlocked) but
    // nothing has been bought — the CTA must stay a purchase, not turn
    // into a dead "premium is on" button. See PremiumService.ownsPlan.
    // Someone who bought a smaller shared plan can still move up to a
    // bigger one — the CTA stays a purchase for them, only for a plan
    // that covers more people than the one they already have. (A
    // person covered by someone else's plan, or already on this plan
    // or a bigger one, still sees the dead "premium is on" state.)
    final ownedSeats = premium.planSeats ?? 0;
    final upgrading = premium.planKind != null && _kind.seats > ownedSeats;
    final owned = premium.ownsPlan && !upgrading;
    // A plan the person can still look after (running, cancelled-but-
    // running, paused): the button opens its management page instead of
    // the old dead "premium is on". Not while they are looking at a
    // bigger plan than their own — then the button is the upgrade
    // purchase ("switch to this plan for …"), and management stays
    // reachable from Settings.
    final manage = premium.hasSubscription && !upgrading;
    final ending = _TrialHeroCopy.of(premium);

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
                  if (owned)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.sage.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('already yours'.tr,
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
                    Entrance(
                      child: _Hero(
                        kind: _kind,
                        fromOnboarding: widget.triggerSource == 'onboarding',
                        fromPartnerLinked: widget.triggerSource == 'partner_linked',
                        chipText: offerTrial
                            ? '${premium.trialDays} ${'free days'.tr}'
                            : winback != null
                                ? '−$winback%'
                                : ending?.chip,
                        headline: winback != null
                            ? 'welcome back'.tr
                            : ending?.headline,
                        subline: winback != null
                            ? '${'your entries and lists are safe — a personal offer just for you, until'.tr} ${formatSubscriptionDate(premium.winbackExpiresAt!)}'
                            : ending?.subline,
                      ),
                    ),
                    if (ending != null && winback == null) ...[
                      const SizedBox(height: 16),
                      Entrance(
                        delay: const Duration(milliseconds: 40),
                        child: _TrialEndsCard(
                          expired: premium.trialExpired,
                          loggedCount: premium.trialLoggedCount,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Entrance(
                      delay: const Duration(milliseconds: 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('who is this for?'.tr,
                              style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                          const SizedBox(height: 10),
                          _KindToggle(
                            kind: _kind,
                            onChanged: (k) => setState(() => _kind = k),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Entrance(
                      delay: const Duration(milliseconds: 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('for how long?'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                          const SizedBox(height: 10),
                          _DurationList(
                            kind: _kind,
                            selected: _duration,
                            discountPercent: winback,
                            onChanged: (d) => setState(() => _duration = d),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    ScrollReveal(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('what\'s included'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                          const SizedBox(height: 10),
                          const _FeatureCard(),
                        ],
                      ),
                    ),
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
                            Text('gift a subscription to someone close'.tr,
                                style: SeenlyText.serif(
                                    italic: true, size: 12.5, color: SeenlyPalette.accent)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PromoCodeField(
                      expanded: _showPromoField,
                      controller: _promoController,
                      onToggle: () => setState(() => _showPromoField = !_showPromoField),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
              decoration: ClayBoxDecoration(
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
                        onTap: manage
                            ? () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => const ManageSubscriptionScreen(),
                                ))
                            : owned
                            ? () {}
                            : offerTrial
                                ? _startTrial
                                : _purchase,
                        scaleTo: 0.97,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: owned && !manage
                                ? SeenlyPalette.inkFaint
                                : SeenlyPalette.accent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          alignment: Alignment.center,
                          child: (_purchasing || _startingTrial)
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.accentOnAccent),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!owned && offerTrial) ...[
                                      Icon(Icons.hourglass_top_outlined,
                                          size: 16, color: SeenlyPalette.accentOnAccent),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      manage
                                          ? 'manage subscription'.tr
                                          : owned
                                          ? 'premium is on'.tr
                                          : offerTrial
                                              ? 'start your free trial'.tr
                                              : '${(upgrading ? 'switch to this plan for' : 'go premium for').tr} $price ₽',
                                      style: SeenlyText.serif(
                                          italic: true,
                                          size: 15,
                                          color: SeenlyPalette.accentOnAccent),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offerTrial && !owned
                          ? '${'then'.tr} $price ₽ ${'for the plan above · no card needed now'.tr}'
                          : winback != null
                              ? '${'personal offer'.tr} −$winback% · ${'applied automatically'.tr}'
                          : ending != null
                              ? 'no card is linked — nothing is charged by itself'.tr
                              : _duration == PremiumDuration.month
                              ? '${'then'.tr} $perMonth ₽ ${'per month · cancel anytime'.tr}'
                              : '≈ $perMonth ₽/${'mo'.tr} · ${'one payment for the whole period'.tr}',
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder),
                    ),
                    const SizedBox(height: 10),
                    _LegalFooter(restoring: _restoring, onRestore: _restorePurchases),
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

/// Restore purchases · Terms of Use · Privacy Policy — the one row App
/// Store review (and, in spirit, honesty toward the person paying)
/// expects within reach of the buy button, not buried in Settings. Kept
/// tiny and low-contrast on purpose: this is fine print, not a fourth
/// call-to-action competing with the real one above it.
class _LegalFooter extends StatelessWidget {
  final bool restoring;
  final VoidCallback onRestore;
  const _LegalFooter({required this.restoring, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final style = SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder);
    final dot = Text(' · ', style: style);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GestureDetector(
          onTap: restoring ? null : onRestore,
          child: restoring
              ? SizedBox(
                  width: 60,
                  height: 12,
                  child: Center(
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation(SeenlyPalette.placeholder)),
                    ),
                  ),
                )
              : Text('restore purchases'.tr, style: style),
        ),
        dot,
        GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const EulaScreen())),
          child: Text('terms of use'.tr, style: style),
        ),
        dot,
        GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          child: Text('privacy policy'.tr, style: style),
        ),
      ],
    );
  }
}

/// What the paywall says about a free period that is running out or has
/// run out — null for everyone else (never trialed, fresh trial with
/// plenty of time, or already an owner), in which case the screen is
/// exactly what it always was. Everything here (chip, headline, the
/// "what changes" card) appears only for the last ~2 days of a free
/// period and after its end, so someone opening the paywall on day one
/// isn't already being told it's over.
class _TrialHeroCopy {
  final String? chip;
  final String headline;
  final String subline;
  const _TrialHeroCopy(this.chip, this.headline, this.subline);

  static _TrialHeroCopy? of(PremiumService premium) {
    if (premium.ownsPlan) return null;
    if (premium.trialExpired) {
      return _TrialHeroCopy(
        null,
        'your free period has ended'.tr,
        'your entries and lists are safe — only the limits are back. bring unlimited back whenever you like'.tr,
      );
    }
    final left = premium.trialTimeLeft;
    if (!premium.trialActive || left == null) return null;
    if (left > const Duration(hours: 48)) return null;
    return _TrialHeroCopy(
      trialLeftLabel(left),
      'your free period is almost over'.tr,
      'no card was linked, so nothing is charged on its own — pick a plan to keep everything unlimited'.tr,
    );
  }
}

/// "Here is exactly what changes" — the honest half of the pitch. Lists
/// the free-tier ceilings straight from the constants PremiumService
/// enforces (so the copy can't drift from the rules) and says plainly
/// that nothing the person made is lost.
class _TrialEndsCard extends StatelessWidget {
  final bool expired;
  final int loggedCount;
  const _TrialEndsCard({required this.expired, required this.loggedCount});

  @override
  Widget build(BuildContext context) {
    Widget row(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.remove, size: 14, color: SeenlyPalette.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: SeenlyText.serif(size: 13, color: SeenlyPalette.ink)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (expired ? 'back on the free plan' : 'when it ends, you\'re on the free plan').tr,
            style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6),
          ),
          row('${'Teamira questions a month'.tr}: ${PremiumService.freeAiAsksPerMonth}'),
          row('${'favorite titles kept on the free plan'.tr}: ${PremiumService.freeFavoritesLimit}'),
          row('${'custom lists'.tr}: ${PremiumService.freeListsLimit}'),
          const SizedBox(height: 10),
          Text(
            'your entries, ratings and lists stay exactly as they are'.tr,
            style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
          ),
          if (loggedCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${'things you did during the free period'.tr}: $loggedCount',
              style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.placeholder),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final PremiumPlanKind kind;
  final bool fromOnboarding;
  // Set when this screen was opened right after two accounts freshly
  // linked into a co-viewing couple (see PremiumScreen.triggerSource ==
  // 'partner_linked', screens/shell/root_shell.dart::
  // _maybeShowPartnerLinkedPaywall) — swaps the headline for one that
  // speaks to the moment that just happened, same idea as
  // [fromOnboarding] just above but for a different soft trigger.
  final bool fromPartnerLinked;
  // Text of the hero's little chip — "3 free days" while a trial is on
  // offer, "5 h left" during one. null (not empty) means no chip.
  final String? chipText;
  // Set while a free period is running out or has run out (see
  // _TrialHeroCopy) — replace the headline/subline below wholesale.
  final String? headline;
  final String? subline;
  const _Hero({
    required this.kind,
    this.fromOnboarding = false,
    this.fromPartnerLinked = false,
    this.chipText,
    this.headline,
    this.subline,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: ClayBoxDecoration(boxShadow: SeenlyPalette.softShadow),
        child: Stack(
          children: [
            // The gradient is the whole background until (if ever) a
            // video lands at assets/premium/paywall_bg.mp4 — see
            // _PaywallVideoBackdrop's own doc comment. Kept underneath
            // rather than replaced by it, since the backdrop's own
            // scrim is semi-transparent by design — it's meant to sit
            // over footage, not stand alone over nothing.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      SeenlyPalette.accent.withOpacity(0.94),
                      SeenlyPalette.accent,
                    ],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: _PaywallVideoBackdrop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BreathingGlow(
                        color: SeenlyPalette.accentOnAccent,
                        size: 46,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.auto_awesome, size: 21, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                      if (chipText != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chipText!,
                            style: SeenlyText.mono(
                                size: 10.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('tanè premium'.tr,
                      style: SeenlyText.serif(
                          italic: true, size: 22, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                  const SizedBox(height: 4),
                  Text(
                    headline ??
                    (fromPartnerLinked
                        ? 'you\'re linked — go unlimited together'.tr
                        : fromOnboarding
                            ? (kind == PremiumPlanKind.individual
                                ? 'unlimited asks, from day one'.tr
                                : 'unlimited asks, together, from day one'.tr)
                            : (kind == PremiumPlanKind.individual
                                ? 'unlimited asks, every night'.tr
                                : 'unlimited asks, together'.tr)),
                    style: SeenlyText.serif(
                        size: 15.5, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subline ??
                    (fromPartnerLinked
                        ? 'when one of you has premium, your shared watch list has no limit — for both of you'.tr
                        : switch (kind) {
                            PremiumPlanKind.couple =>
                              'one cozy evening for two — no limits for either of you'.tr,
                            PremiumPlanKind.family =>
                              'one plan for up to four of you — a shared evening with no limits for anyone'.tr,
                            PremiumPlanKind.individual =>
                              'a little more room for your evenings'.tr,
                          }),
                    style: SeenlyText.serif(size: 13, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet, optional layer behind the hero's gradient — activates the
/// moment a file lands at `assets/premium/paywall_bg.mp4` (same
/// wildcard-directory setup as assets/onboarding/, see pubspec.yaml)
/// and stays invisible until then. Deliberately doesn't touch
/// [_Hero]'s gradient itself: this widget only ever adds a video layer
/// *underneath* that gradient (now rendered semi-transparent above it),
/// so removing this whole file, or simply never dropping a video in,
/// leaves the exact solid-gradient hero the screen always had.
///
/// Same shape as onboarding_screen.dart's own `_VideoBackdrop` — muted,
/// looping, BoxFit.cover — with one addition: `.catchError` on
/// [VideoPlayerController.initialize], since a missing asset here isn't
/// exceptional the way it would be in onboarding (which ships its video
/// as a real asset already) — it's the expected, ordinary state until
/// this screen's video is actually added.
class _PaywallVideoBackdrop extends StatefulWidget {
  const _PaywallVideoBackdrop();

  @override
  State<_PaywallVideoBackdrop> createState() => _PaywallVideoBackdropState();
}

class _PaywallVideoBackdropState extends State<_PaywallVideoBackdrop> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.asset('assets/premium/paywall_bg.mp4');
    _controller = controller;
    controller
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        controller.play();
      }).catchError((_) {
        // Expected until a video file actually exists at that path —
        // see this class's own doc comment. _ready simply never
        // becomes true, so build() below keeps returning nothing and
        // _Hero's gradient stands alone, exactly as it did before this
        // widget existed.
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null || controller.value.size.width <= 0) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        // Scrim in the same accent tone _Hero's gradient already uses,
        // so text legibility doesn't depend on what's actually in the
        // footage — a lighter shot and a dark one both end up under the
        // same accent-tinted wash.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.accent.withOpacity(0.55),
                SeenlyPalette.accent.withOpacity(0.82),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KindToggle extends StatelessWidget {
  final PremiumPlanKind kind;
  final ValueChanged<PremiumPlanKind> onChanged;
  const _KindToggle({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _KindCard(
                icon: Icons.person_outline,
                title: 'just me'.tr,
                subtitle: 'for you alone'.tr,
                selected: kind == PremiumPlanKind.individual,
                onTap: () => onChanged(PremiumPlanKind.individual),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KindCard(
                icon: Icons.favorite_outline,
                title: 'a couple'.tr,
                subtitle: 'a better deal for two'.tr,
                badge: 'better value'.tr,
                selected: kind == PremiumPlanKind.couple,
                onTap: () => onChanged(PremiumPlanKind.couple),
              ),
            ),
          ],
        ),
        // Third option, a full row of its own: a circle of three or four
        // is what the co-viewing "company" already is, and the card has
        // to say "up to 4" without wrapping — which two-across cards
        // this narrow can't do. Sits under the pair rather than between
        // the two so the solo/couple choice keeps reading as the main
        // fork, and the bigger circle as the "or, for a company" one.
        const SizedBox(height: 10),
        _KindCard(
          wide: true,
          icon: Icons.groups_2_outlined,
          title: 'family & friends'.tr,
          subtitle: 'up to four of you, one plan'.tr,
          badge: 'up to 4'.tr,
          selected: kind == PremiumPlanKind.family,
          onTap: () => onChanged(PremiumPlanKind.family),
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
  // Full-width layout: icon on the left, text beside it, instead of the
  // stacked half-width layout the two side-by-side cards use.
  final bool wide;
  final VoidCallback onTap;
  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.selected,
    this.wide = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.97,
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
            child: wide
                ? Row(
                    children: [
                      Icon(icon,
                          size: 22,
                          color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: SeenlyText.serif(
                                    size: 14.5,
                                    weight: FontWeight.w600,
                                    color: SeenlyPalette.ink)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                          ],
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle, size: 17, color: SeenlyPalette.accent),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(icon,
                              size: 19,
                              color: selected ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
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
  // The win-back percent, when open: prices are drawn after it, struck
  // through next to what the same option costs without it.
  final int? discountPercent;
  const _DurationList({
    required this.kind,
    required this.selected,
    required this.onChanged,
    this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      // purchasableDurations, not PremiumDuration.values — see that
      // list's own doc comment on why sixMonths is excluded here.
      children: purchasableDurations.map((d) {
        final off = discountPercent;
        final basePrice = PremiumPricing.priceFor(kind, d);
        final basePerMonth = PremiumPricing.perMonth(kind, d);
        final price = off == null ? basePrice : PremiumPricing.discounted(basePrice, off);
        final perMonth = off == null ? basePerMonth : PremiumPricing.discounted(basePerMonth, off);
        // With the personal discount the badge and the strike-through
        // are about *it* (same plan, with and without), not about the
        // longer-plan saving, so the two never stack into a number that
        // matches nothing on screen.
        final save = off ?? PremiumPricing.savePercent(kind, d);
        return Padding(
          // Extra room above the year row only, for the "best value"
          // ribbon that sits half outside its top edge.
          padding: EdgeInsets.only(bottom: 10, top: d == PremiumDuration.year ? 8 : 0),
          child: _DurationRow(
            label: switch (d) {
              PremiumDuration.month => 'month'.tr,
              PremiumDuration.threeMonths => 'three months'.tr,
              PremiumDuration.sixMonths => 'six months'.tr,
              PremiumDuration.year => 'year'.tr,
            },
            perPersonNote: kind == PremiumPlanKind.individual
                ? null
                : '≈ ${PremiumPricing.perPersonPerMonth(kind, d)} ₽/${'mo'.tr} ${'per person'.tr}',
            price: price,
            perMonth: perMonth,
            // What the same plan costs per month when paid monthly —
            // drawn struck through next to the longer options' monthly
            // equivalent, so the saving is something you see, not just
            // a percentage you have to trust.
            monthlyPrice: off != null
                ? basePerMonth
                : PremiumPricing.perMonth(kind, PremiumDuration.month),
            freeMonths: off != null ? 0 : PremiumPricing.freeMonths(kind, d),
            savePercent: save,
            // The anchor: the longest option is the one we'd like most
            // people to land on, so it alone gets the ribbon and a
            // permanently warmer border — the other two stay neutral.
            best: d == PremiumDuration.year,
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
  final int monthlyPrice;
  final int freeMonths;
  final int savePercent;
  final bool best;
  final bool selected;
  final VoidCallback onTap;
  const _DurationRow({
    required this.label,
    this.perPersonNote,
    required this.price,
    required this.perMonth,
    required this.monthlyPrice,
    required this.freeMonths,
    required this.savePercent,
    required this.best,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final mo = 'mo'.tr;
    // Only worth drawing the struck-through monthly price when the
    // longer option actually undercuts it.
    final showStrike = savePercent > 0 && monthlyPrice > perMonth;
    // The small line under the label: how many months come free (only
    // on options that really save at least one). The shared plans' per-
    // person note is drawn under it, not instead of it.
    final String? detail = freeMonths >= 1
        ? (ru
            ? '≈ ${ruCount(freeMonths, one: 'месяц', few: 'месяца', many: 'месяцев', englishOne: 'month', englishOther: 'months')} в подарок'
            : '≈ ${freeMonths == 1 ? '1 month' : '$freeMonths months'} free')
        : null;

    final row = PressScale(
      onTap: onTap,
      scaleTo: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent.withOpacity(0.1) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? SeenlyPalette.accent
                : best
                    ? SeenlyPalette.accent.withOpacity(0.45)
                    : SeenlyPalette.border,
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
                  // Both lines when a shared plan has both to say: the
                  // per-person price is the whole point of buying for
                  // several people, so it can't be hidden on exactly the
                  // long options where the "months free" line also shows.
                  for (final line in [detail, perPersonNote])
                    if (line != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // The monthly equivalent leads — big, the number people
            // actually compare against their other subscriptions — and
            // the one-off total drops to fine print beneath it. (The
            // buy button itself still states the exact total charged.)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (showStrike) ...[
                      Text(
                        '$monthlyPrice',
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)
                            .copyWith(decoration: TextDecoration.lineThrough),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text('$perMonth ₽',
                        style: SeenlyText.serif(
                            size: 19, weight: FontWeight.w700, color: SeenlyPalette.ink)),
                    Text('/$mo',
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
                  ],
                ),
                if (price != perMonth) ...[
                  const SizedBox(height: 2),
                  Text(
                    ru ? '$price ₽ разом' : '$price ₽ billed once',
                    style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (!best) return row;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        row,
        Positioned(
          top: -8,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SeenlyPalette.coral,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              ru ? 'самый выгодный' : 'best value',
              style: SeenlyText.mono(
                  size: 8.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard();

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
          _FeatureRow(
            icon: Icons.auto_awesome_outlined,
            title: 'unlimited tanè asks'.tr,
            subtitle: 'free tier — 3 a month'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.favorite_outline,
            title: 'as many favorite films as you like'.tr,
            subtitle: 'free tier — up to 5'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.playlist_add_outlined,
            title: 'as many lists as you like'.tr,
            subtitle: 'free tier — up to 5 lists'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.rocket_launch_outlined,
            title: '"space shuttle" log theme'.tr,
            subtitle: 'exclusive to premium'.tr,
          ),
          const _FeatureDivider(),
          // The two colour moods in Settings > appearance — locked there for
          // everyone without premium (see settings_screen.dart, `isFlavor`).
          _FeatureRow(
            icon: Icons.palette_outlined,
            title: at('цветные темы: апельсиновая и клубничная', 'colour themes: tangerine and strawberry'),
            subtitle: at(
              'тёплое настроение для всего приложения — в настройках, в разделе внешнего вида',
              'a warm mood for the whole app — in Settings, under appearance',
            ),
          ),
          const _FeatureDivider(),
          // The home-screen widget (HomeWidgetService shows "unlock premium
          // for this widget" without it). Listed on Android only for now: the
          // iOS WidgetKit extension is written but not yet a target in the
          // Xcode project (ios/SeenlyWidget/HomeWidgetSetup.md), so an iPhone
          // would be sold a widget it can't add. When the iOS target exists,
          // drop the platform check.
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            _FeatureRow(
              icon: Icons.widgets_outlined,
              title: at('виджет на главном экране', 'home-screen widget'),
              subtitle: at(
                'ближайший вечер вдвоём, подборка дня или ваша серия — прямо на экране телефона',
                'your next evening together, today’s pick or your streak — right on your phone’s home screen',
              ),
            ),
            const _FeatureDivider(),
          ],
          _FeatureRow(
            icon: Icons.auto_stories_outlined,
            title: 'keepsake export (pdf)'.tr,
            subtitle: 'your diary or your wrapped, as a pdf to save or print'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.calendar_month_outlined,
            title: 'a wrapped of your own'.tr,
            subtitle: 'a trip, a season, a relationship — any stretch you name'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.playlist_add_check_rounded,
            title: at('общий список без лимита', 'a shared list with no limit'),
            subtitle: at(
              'бесплатно в общем списке помещается до 5 запланированных тайтлов; с премиумом — сколько угодно, и одна подписка снимает лимит для всего круга',
              'free, your shared list holds up to 5 planned titles; premium lifts the cap — and one subscription covers the whole circle',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.people_outline,
            title: at('круг из трёх и четырёх', 'a circle of three or four'),
            subtitle: at(
              'вдвоём всегда бесплатно. третий и четвёртый человек в круге — премиум. а в комнату просмотра можно позвать до трёх друзей гостями — это бесплатно для всех',
              'the two of you is always free. a third and fourth person in the circle is premium. but you can invite up to three friends into a watching room as guests — free for everyone',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.spa_outlined,
            title: at('дзен-режим для просмотра и чтения', 'zen mode for watching and reading together'),
            subtitle: at(
              'тихая комната: у фильма — светящиеся огоньки, у книги — мягкий фон и плавное перелистывание, и эмоции в одно касание. комнаты, голос и чат остаются бесплатными',
              'a quiet room: glowing orbs for a film, a soft backdrop and gliding pages for a book, and one-tap feelings. rooms, voice and chat stay free',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.timeline_rounded,
            title: at('моменты вашего вечера', 'the moments of your evening'),
            subtitle: at(
              'шкала того, где вы вместе смеялись и ахали: в фильме, в книге (по главам) и в игре (победы и поражения) — и для вечеров, которые вы уже провели',
              'a timeline of where you laughed and gasped together: in a film, a book (by chapter) or a game (wins and losses) — including evenings you have already had',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.menu_book_outlined,
            title: at('ваш общий альбом', 'your shared album'),
            subtitle: at(
              'записки до вечера, капсулы времени и годовщина. одна подписка на двоих; читать можно всегда, даже после её окончания',
              'notes before the evening, time capsules and your anniversary. one subscription covers both of you; reading is always free',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.collections_bookmark_outlined,
            title: at('книга ваших вечеров', 'the book of your evenings'),
            subtitle: at(
              'рецензии и моменты ваших вечеров — в pdf, который можно сохранить, распечатать или подарить. одна подписка на весь круг',
              'the reviews and moments of your evenings as a pdf to save, print or give. one subscription covers the whole circle',
            ),
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.bar_chart_outlined,
            title: 'you vs your circle'.tr,
            subtitle: 'in wrapped and stats — who suggests more of what you watch'.tr,
          ),
          const _FeatureDivider(),
          _FeatureRow(
            icon: Icons.show_chart,
            title: 'your trend'.tr,
            subtitle: 'a month-by-month chart of your own activity, not just a snapshot'.tr,
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
        child: CozyDivider(height: 1, color: SeenlyPalette.border),
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

/// "есть промокод?" — collapsed by default (see planning doc's UI spec
/// for this screen), since most people buying premium were never
/// referred and shouldn't see an extra field competing with the
/// purchase button. Deliberately does no client-side validation of the
/// code itself: whether it exists, belongs to someone else, or was
/// already spent is only knowable server-side (see backend routers/
/// premium.py::purchase) — an invalid code surfaces as the normal
/// ApiException SnackBar in _PremiumScreenState._purchase, same as any
/// other purchase failure, rather than this field guessing at validity
/// up front.
class _PromoCodeField extends StatelessWidget {
  final bool expanded;
  final TextEditingController controller;
  final VoidCallback onToggle;

  const _PromoCodeField({
    required this.expanded,
    required this.controller,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Center(
        child: GestureDetector(
          onTap: onToggle,
          child: Text(
            'have a promo code?'.tr,
            style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('promo code'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          style: SeenlyText.mono(size: 13, color: SeenlyPalette.ink),
          decoration: InputDecoration(
            hintText: 'e.g. AB4QPCCL'.tr,
            hintStyle: SeenlyText.mono(size: 13, color: SeenlyPalette.inkFaint),
            filled: true,
            fillColor: SeenlyPalette.paper,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
