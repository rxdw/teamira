import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_translations.dart';
import '../../services/premium_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';

/// "30 days" / "30 дней" — through ruCount, because the bare 'days' key in
/// the translation table has two Russian forms and can't pick one.
String _daysLabel(int n) =>
    ruCount(n, one: 'день', few: 'дня', many: 'дней', englishOne: 'day', englishOther: 'days');

/// "12.05.2026" — one short numeric date, the same in both languages.
String formatSubscriptionDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Where a person looks after and, if they must, leaves a plan they
/// bought: what state it is in, a month's pause offered *before* the
/// cancel button, and cancelling itself as the quiet last option
/// (backend app/subscription.py has the rules; this only shows them).
///
/// A lapsed plan has nothing to manage — it belongs on the paywall, with
/// the win-back offer if that is still open — so this screen sends it
/// there instead of showing a dead page.
class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() => _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) _toast(done.tr);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('something went wrong — please try again'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openCancelSheet() async {
    final premium = context.read<PremiumService>();
    final result = await showModalBottomSheet<_CancelResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelSheet(
        canPause: premium.pauseAvailable,
        pauseDays: premium.pauseDays,
        planKind: premium.planKind,
      ),
    );
    if (!mounted || result == null) return;
    if (result.pause) {
      await _run(() => premium.pauseSubscription(source: 'cancel_sheet'),
          done: 'paused — see you soon');
    } else {
      await _run(() => premium.cancelSubscription(reason: result.reason),
          done: 'subscription cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumService>();

    // Nothing to manage on a lapsed or never-bought account: back out to
    // whatever the caller was on (usually the paywall's own button).
    if (!premium.hasSubscription) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return Scaffold(backgroundColor: SeenlyPalette.background);
    }

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          children: [
            Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: SeenlyPalette.ink),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ]),
            const SizedBox(height: 4),
            Entrance(
              child: Text('your subscription'.tr, style: SeenlyText.screenTitle),
            ),
            const SizedBox(height: 16),
            Entrance(delay: const Duration(milliseconds: 60), child: _StatusCard(premium: premium)),
            const SizedBox(height: 18),
            if (premium.isCancelling)
              Entrance(
                delay: const Duration(milliseconds: 120),
                child: _KeepCard(
                  busy: _busy,
                  onKeep: () => _run(premium.resumeSubscription, done: 'welcome back — it is yours again'),
                ),
              )
            else if (premium.isPaused) ...[
              Entrance(
                delay: const Duration(milliseconds: 120),
                child: _PrimaryButton(
                  label: 'resume now'.tr,
                  busy: _busy,
                  onTap: () => _run(premium.resumeSubscription, done: 'premium is back'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'the unused days of the break come back to you, nothing is lost'.tr,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 10.5),
              ),
            ] else if (premium.pauseAvailable)
              Entrance(
                delay: const Duration(milliseconds: 120),
                child: _PauseCard(
                  days: premium.pauseDays,
                  busy: _busy,
                  onPause: () =>
                      _run(() => premium.pauseSubscription(source: 'manage'), done: 'paused — see you soon'),
                ),
              ),
            const SizedBox(height: 22),
            if (!premium.isCancelling)
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _openCancelSheet,
                  child: Text(
                    'cancel subscription'.tr,
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ),
            if (premium.planKind == PremiumPlanKind.couple ||
                premium.planKind == PremiumPlanKind.family) ...[
              const SizedBox(height: 8),
              Text(
                (premium.planKind == PremiumPlanKind.family
                        ? 'on a family plan the other seats follow yours'
                        : 'on a couple plan your partner’s seat follows yours')
                    .tr,
                textAlign: TextAlign.center,
                style: SeenlyText.mono(size: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.premium});
  final PremiumService premium;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color tint;
    final String title;
    final String line;

    if (premium.isPaused) {
      icon = Icons.pause_circle_outline;
      tint = SeenlyPalette.periwinkle;
      title = 'on a break'.tr;
      final until = premium.pausedUntil;
      line = until == null ? '' : '${'back on'.tr} ${formatSubscriptionDate(until)}';
    } else if (premium.isCancelling) {
      icon = Icons.hourglass_bottom_outlined;
      tint = SeenlyPalette.coral;
      title = 'cancelled'.tr;
      final end = premium.cancelEffectiveAt;
      line = end == null ? '' : '${'premium works until'.tr} ${formatSubscriptionDate(end)}';
    } else {
      icon = Icons.auto_awesome;
      tint = SeenlyPalette.sage;
      title = 'premium is on'.tr;
      final renews = premium.paidUntil;
      line = renews == null ? '' : '${'renews on'.tr} ${formatSubscriptionDate(renews)}';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: tint.withOpacity(0.35), shape: BoxShape.circle),
            child: Icon(icon, color: SeenlyPalette.ink, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SeenlyText.cardTitle),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(line, style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted)),
                ],
                const SizedBox(height: 3),
                Text(_planLabel(premium), style: SeenlyText.mono(size: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _planLabel(PremiumService p) {
    final kind = switch (p.planKind) {
      PremiumPlanKind.couple => 'a couple'.tr,
      PremiumPlanKind.family => 'family & friends'.tr,
      _ => 'just me'.tr,
    };
    final months = p.planDuration?.months;
    if (months == null) return kind;
    return '$kind · $months ${'mo'.tr}';
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

class _PauseCard extends StatelessWidget {
  const _PauseCard({required this.days, required this.busy, required this.onPause});
  final int days;
  final bool busy;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SeenlyPalette.periwinkle.withOpacity(0.32),
            SeenlyPalette.pink.withOpacity(0.28),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('need a breather?'.tr, style: SeenlyText.cardTitle),
          const SizedBox(height: 6),
          Text(
            '${'freeze it for'.tr} ${_daysLabel(days)}. ${'no payment for that time, it comes back by itself'.tr}',
            style: SeenlyText.bodyText,
          ),
          const SizedBox(height: 14),
          _PrimaryButton(label: 'pause for a month'.tr, busy: busy, onTap: onPause),
        ],
      ),
    );
  }
}

class _KeepCard extends StatelessWidget {
  const _KeepCard({required this.busy, required this.onKeep});
  final bool busy;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('changed your mind?'.tr, style: SeenlyText.cardTitle),
          const SizedBox(height: 6),
          Text('keep the subscription — nothing is charged now'.tr, style: SeenlyText.bodyText),
          const SizedBox(height: 14),
          _PrimaryButton(label: 'keep my subscription'.tr, busy: busy, onTap: onKeep),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap, this.busy = false});
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent,
          borderRadius: BorderRadius.circular(99),
          boxShadow: SeenlyPalette.softShadow,
        ),
        alignment: Alignment.center,
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
              )
            : Text(label,
                style: SeenlyText.serif(
                    italic: true,
                    size: 15,
                    weight: FontWeight.w600,
                    color: SeenlyPalette.accentOnAccent)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cancel sheet
// ---------------------------------------------------------------------------

class _CancelResult {
  const _CancelResult.pause()
      : pause = true,
        reason = null;
  const _CancelResult.cancel(this.reason) : pause = false;
  final bool pause;
  final String? reason;
}

/// Closed vocabulary — these strings go to analytics as-is, and the
/// labels are looked up from them.
const _cancelReasons = <String>[
  'too expensive',
  'not using it enough',
  'missing something',
  'just a break',
  'other',
];

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.canPause, required this.pauseDays, required this.planKind});
  final bool canPause;
  final int pauseDays;
  // Which plan is being cancelled — a shared one (couple / family) also
  // ends the other people's seats, and the sheet says so.
  final PremiumPlanKind? planKind;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          22, 14, 22, 22 + MediaQuery.of(context).viewPadding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: SeenlyPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('before you go'.tr, style: SeenlyText.screenTitle),
            const SizedBox(height: 6),
            Text(
              'premium keeps working until the end of the period you paid for'.tr,
              style: SeenlyText.bodyText,
            ),
            if (widget.canPause) ...[
              const SizedBox(height: 16),
              _PauseOffer(
                days: widget.pauseDays,
                onTap: () => Navigator.of(context).pop(const _CancelResult.pause()),
              ),
            ],
            const SizedBox(height: 18),
            Text('what made you decide? (optional)'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _cancelReasons)
                  _ReasonChip(
                    label: r.tr,
                    selected: _reason == r,
                    onTap: () => setState(() => _reason = _reason == r ? null : r),
                  ),
              ],
            ),
            if (widget.planKind == PremiumPlanKind.couple ||
                widget.planKind == PremiumPlanKind.family) ...[
              const SizedBox(height: 14),
              Text(
                (widget.planKind == PremiumPlanKind.family
                        ? 'the other seats end together with yours'
                        : 'your partner’s seat ends together with yours')
                    .tr,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.coral),
              ),
            ],
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'keep my subscription'.tr,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(_CancelResult.cancel(_reason)),
                child: Text(
                  'cancel at the end of the period'.tr,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseOffer extends StatelessWidget {
  const _PauseOffer({required this.days, required this.onTap});
  final int days;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SeenlyPalette.periwinkle.withOpacity(0.32),
              SeenlyPalette.pink.withOpacity(0.28),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline, color: SeenlyPalette.ink, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('pause instead'.tr, style: SeenlyText.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    '${_daysLabel(days)} · ${'no payment, comes back by itself'.tr}',
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 16, color: SeenlyPalette.ink),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? SeenlyPalette.accent : SeenlyPalette.border),
        ),
        child: Text(
          label,
          style: SeenlyText.mono(
            size: 11,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted,
          ),
        ),
      ),
    );
  }
}
