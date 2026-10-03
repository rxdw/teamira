import 'package:flutter/material.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/referral.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';
import '../../widgets/settings_motion.dart';
import '../../widgets/soft_motion.dart';
import '../../theme/clay_kit.dart';

/// "Мои приглашения" — everything about the referral reward program in
/// one place: cumulative progress toward the next premium-days
/// milestone, this account's own shareable discount code, and every
/// invited person with live progress against the three real-person
/// conditions (see backend/app/routers/referrals.py for what those are
/// and why — no SMS verification, just entries/streak/time). Loading
/// this screen IS the refresh: GET /referrals/status also recomputes
/// and verifies pending invitees server-side, there's no separate pull
/// to check for updates.
///
/// Deliberately a separate screen from FriendsScreen/InviteFriendsSheet
/// (the sincerity-per-friend invite graph) — same underlying "who invited
/// whom" fact, but a different reward track with its own conditions and
/// its own payout, and mixing the two into one screen would make it
/// unclear which bonus a given number belongs to.
class MyReferralsScreen extends StatefulWidget {
  const MyReferralsScreen({super.key});

  @override
  State<MyReferralsScreen> createState() => _MyReferralsScreenState();
}

class _MyReferralsScreenState extends State<MyReferralsScreen> {
  ReferralStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final status = await context.read<AppState>().referrals.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('code copied'.tr)));
  }

  void _share(String code, int discountPercent) {
    final text = LocaleService.appIsRussian
        ? 'держи мой промокод на $discountPercent% скидку на premium в teamira: $code'
        : 'here\'s my code for $discountPercent% off premium on teamira: $code';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        title: Text('my invites'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
      ),
      body: SoftSwap(
        expand: true,
        alignment: Alignment.topCenter,
        rise: 0.015,
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey<String>(_loading ? 'loading' : (_status == null ? 'error' : 'list')),
          child: _loading
              ? const Center(child: ThemedLoadingIndicator())
              : _status == null
                  ? Center(
                  child: Text("couldn't load your invites — try again in a bit".tr,
                      style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted)),
                )
                  : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: staggerChildren([
                      _ProgressCard(status: _status!),
                      const SizedBox(height: 16),
                      if (_status!.promoCode != null)
                        _PromoCard(
                          code: _status!.promoCode!,
                          discountPercent: _status!.promoDiscountPercent,
                          onCopy: () => _copyCode(_status!.promoCode!),
                          onShare: () => _share(_status!.promoCode!, _status!.promoDiscountPercent),
                        ),
                      const SizedBox(height: 20),
                      if (_status!.referred.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Text(
                            'invite a friend to see them here'.tr,
                            textAlign: TextAlign.center,
                            style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
                          ),
                        )
                      else ...[
                        Text('invited'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                        const SizedBox(height: 10),
                        for (final r in _status!.referred) ...[
                          _ReferredRow(referred: r),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final ReferralStatus status;
  const _ProgressCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final next = status.nextMilestoneAt;
    final nextDays = status.nextMilestoneDays;
    final progress = next != null && next > 0 ? (status.verifiedCount / next).clamp(0.0, 1.0) : 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('invite a friend — you both get premium'.tr,
              style: SeenlyText.serif(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${'each friend who sticks around gets'.tr} ${status.referredWelcomeDays} ${'days of premium too'.tr}',
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(height: 6),
          Text(
            next != null
                ? '${'confirmed'.tr}: ${status.verifiedCount}/$next — ${'next reward'.tr}: +$nextDays ${'days of premium'.tr}'
                : '${'confirmed'.tr}: ${status.verifiedCount} — ${'every reward earned so far'.tr}',
            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // The bar fills from empty to where the person actually is.
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: SeenlyPalette.background,
                valueColor: AlwaysStoppedAnimation(SeenlyPalette.accent),
              ),
            ),
          ),
          if (status.pendingCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${status.pendingCount} ${'still confirming'.tr}',
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Партнёрский уровень" — the recurring reward for prolific referrers
/// (bloggers/influencers) past the fixed 1/5/10 milestone ladder: no
/// longer a standing discount, but the recurring milestone-days ladder
/// (see backend/app/routers/referrals.py::_next_milestone /
/// RECURRING_MILESTONE_STEP) — same +3/+30/+90 progress card above
/// keeps working for this automatically since it's driven off
/// next_milestone_at/next_milestone_days either way, so there's nothing
/// separate to render here anymore.

class _PromoCard extends StatelessWidget {
  final String code;
  final int discountPercent;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _PromoCard({
    required this.code,
    required this.discountPercent,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('your promo code'.tr, style: SeenlyText.serif(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            '${'gives whoever uses it'.tr} $discountPercent% ${'off their first premium purchase'.tr}',
            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 12),
          PressScale(
            onTap: onCopy,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(code,
                      style: SeenlyText.mono(size: 18, color: SeenlyPalette.ink, weight: FontWeight.w700)
                          .copyWith(letterSpacing: 3)),
                  const SizedBox(width: 10),
                  Icon(Icons.copy_rounded, size: 14, color: SeenlyPalette.inkFaint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
            decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(24)),
            child: PressScale(
              onTap: onShare,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ios_share_rounded, size: 15, color: SeenlyPalette.accentOnAccent),
                  const SizedBox(width: 8),
                  Text('share code'.tr,
                      style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferredRow extends StatelessWidget {
  final ReferredUser referred;
  const _ReferredRow({required this.referred});

  String _statusLabel() {
    if (referred.isRewarded) return 'reward earned'.tr;
    if (referred.isVerified) return 'confirmed'.tr;
    if (referred.isRejected) return 'not counted'.tr;
    return 'confirming'.tr;
  }

  Color _statusColor() {
    if (referred.isRewarded) return SeenlyPalette.accent;
    if (referred.isVerified) return SeenlyPalette.sage;
    if (referred.isRejected) return SeenlyPalette.inkFaint;
    return SeenlyPalette.inkMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,color: SeenlyPalette.paper, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(referred.name,
                    style: SeenlyText.serif(size: 13.5, weight: FontWeight.w700, color: SeenlyPalette.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor().withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(), style: SeenlyText.mono(size: 9.5, color: _statusColor())),
              ),
            ],
          ),
          if (referred.isPending) ...[
            const SizedBox(height: 8),
            Text(
              // Mirrors the exact copy the planning doc asked for: "ждём
              // 5 дней подряд в приложении и от 2 записей, засчитается не
              // раньше [дата]" — spelled out per-condition rather than a
              // single opaque progress bar, so it's clear what's still
              // missing.
              '${'needs'.tr}: '
              '${referred.streakDays}/${referred.streakDaysRequired} ${'days in a row'.tr}, '
              '${referred.entriesCount}/${referred.entriesRequired} ${'entries'.tr} — '
              '${'counts no earlier than'.tr} ${_formatDate(referred.eligibleNotBefore)}',
              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    if (LocaleService.appIsRussian) {
      return '${d.day} ${months[d.month - 1]}';
    }
    return '${d.month}/${d.day}';
  }
}
