import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/recommendation.dart';
import '../../models/sincerity.dart';
import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/settings_motion.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/spend_confirm_sheet.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart' show Entrance, PressScale, Breathe;
import '../../theme/clay_kit.dart';

/// The full picture behind the small SincerityCard on the profile
/// screen: current balance, a plain-language "how this works" section
/// (kept visible, not buried — see the product note that this should
/// never feel like a hidden game mechanic), and the transaction
/// history that makes every change legible after the fact. See
/// backend/app/sincerity.py's module docstring for the underlying
/// design principles this screen is just making readable.
///
/// Every piece of text on this screen goes through [SeenlyText] rather
/// than the ambient Material `Theme.of(context).textTheme` — that
/// theme is never given the app's own typefaces (see app_theme.dart's
/// `textTheme: base.textTheme.apply(...)`, which only recolors it), so
/// reaching for it here silently rendered this one screen in the
/// platform default font while everywhere else in the app used
/// Comfortaa/Unbounded (or Caveat, in the Cozy Diary skin) — the
/// mismatch this file used to have across nearly every label on it.
class SincerityScreen extends StatefulWidget {
  const SincerityScreen({super.key});

  @override
  State<SincerityScreen> createState() => _SincerityScreenState();
}

class _SincerityScreenState extends State<SincerityScreen> {
  SincerityBalance? _balance;
  RecommendationsResponse? _recs;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecommendations();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final balance = await context.read<AppState>().sincerity.me();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'не получилось загрузить — попробуй ещё раз'.tr;
        _loading = false;
      });
    }
  }

  // Best-effort and separate from _load(): a failed fetch here just
  // means the "ставки в игре" section stays empty, not that the whole
  // balance screen (the part people actually came for) breaks with it.
  Future<void> _loadRecommendations() async {
    try {
      final recs = await context.read<AppState>().recommendations.list();
      if (!mounted) return;
      setState(() => _recs = recs);
    } catch (_) {
      // Silently skipped — see this method's own docstring above.
    }
  }

  Future<void> _loadMore() async {
    final current = _balance;
    if (current == null || !current.hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final older = await context.read<AppState>().sincerity.me(before: current.history.last.id);
      if (!mounted) return;
      setState(() {
        _balance = current.withMoreHistory(older);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        title: Text('искренность'.tr, style: SeenlyText.serif(size: 17, italic: true)),
      ),
      body: SoftSwap(
        expand: true,
        alignment: Alignment.topCenter,
        rise: 0.015,
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey<String>(_loading ? 'loading' : (_error != null ? 'error' : 'list')),
          child: _loading
              ? const Center(child: ThemedLoadingIndicator(size: 24))
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        // Quiet on purpose (this number is not a score to
                        // chase): the page just settles in from the top.
                        ...staggerChildren([
                          _BalanceHeader(balance: _balance!.balance),
                          const SizedBox(height: 20),
                          const _ExplainerSection(),
                          const SizedBox(height: 24),
                          _PrivacyRow(visible: _balance!.visibleToFriends),
                          if (_balance!.staleItems.any((i) => !i.debtExempt)) ...[
                            const SizedBox(height: 24),
                            _StaleItemsSection(
                              items: _balance!.staleItems,
                              balance: _balance!.balance,
                              onSettled: _load,
                            ),
                          ],
                          if (_recs != null &&
                              (_recs!.outgoing.any((r) => r.isPending) ||
                                  _recs!.incoming.any((r) => r.isPending))) ...[
                            const SizedBox(height: 24),
                            _PendingRecommendationsSection(recs: _recs!),
                          ],
                          const SizedBox(height: 24),
                          Text('история'.tr, style: SeenlyText.sectionTitle),
                          const SizedBox(height: 8),
                        ]),
                        if (_balance!.history.isEmpty)
                          const _EmptyHistory()
                        else
                          // Each history row comes in once, keyed by the
                          // change it records — so rows loaded later
                          // arrive on their own instead of the list
                          // replaying.
                          for (final entry in _balance!.history.indexed)
                            Entrance(
                              key: ValueKey<Object>(entry.$2.id),
                              delay: Duration(milliseconds: entry.$1 < 10 ? 260 + 45 * entry.$1 : 0),
                              duration: const Duration(milliseconds: 420),
                              riseBy: 10,
                              child: _TransactionRow(txn: entry.$2),
                            ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _loadingMore
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  child: Center(
                                    child: BouncingDots(color: SeenlyPalette.inkFaint, dotSize: 4),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  final int balance;
  const _BalanceHeader({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Counts up from zero the first time, and from the old figure to
            // the new one after a refresh — never more than a second.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: balance.toDouble()),
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Text(
                '${value.round()}',
                style: SeenlyText.serif(size: 40, italic: true),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // A very slow glow: the bulb is just there, not asking.
              child: Breathe(
                child: Icon(Icons.wb_incandescent_outlined, size: 20, color: SeenlyPalette.mustard),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'не рейтинг и не уровень — просто число, которое растёт, когда ты честен с собой'.tr,
          style: SeenlyText.serif(size: 14, color: SeenlyPalette.inkMuted),
        ),
      ],
    );
  }
}

class _ExplainerSection extends StatefulWidget {
  const _ExplainerSection();

  @override
  State<_ExplainerSection> createState() => _ExplainerSectionState();
}

class _ExplainerSectionState extends State<_ExplainerSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressScale(
            scaleTo: 0.99,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'как это работает'.tr,
                      style: SeenlyText.serif(size: 15, weight: FontWeight.w600),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.keyboard_arrow_down, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
          ),
          // The text unfolds (the card grows to fit it) rather than jumping.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SoftSwap(
              alignment: Alignment.topLeft,
              rise: 0.02,
              child: !_expanded
                  ? const SizedBox(key: ValueKey<bool>(false), width: double.infinity)
                  : Padding(
              key: const ValueKey<bool>(true),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'начисляется, когда ты:'.tr,
                    style: SeenlyText.serif(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _ExplainerLine(text: 'наконец закрываешь то, что давно висело в планах — посмотрел или честно решил, что это не твоё'.tr),
                  _ExplainerLine(text: 'меняешь старую оценку вместо того, чтобы её защищать'.tr),
                  _ExplainerLine(text: 'бросаешь просмотр и честно пишешь почему'.tr),
                  _ExplainerLine(text: 'возвращаешься к брошенному и всё-таки досматриваешь'.tr),
                  _ExplainerLine(text: 'оцениваешь общий тайтл сам — не подглядывая в оценку партнёра'.tr),
                  _ExplainerLine(text: 'ставишь очки на рекомендацию другу — и попадаешь'.tr),
                  const SizedBox(height: 16),
                  Text(
                    'тратится, когда ты:'.tr,
                    style: SeenlyText.serif(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _ExplainerLine(text: 'ставишь очки на рекомендацию другу — риск того, что она не зайдёт'.tr),
                  _ExplainerLine(text: 'открываешь оценку партнёра раньше, чем оценил тайтл сам'.tr),
                  _ExplainerLine(text: 'платишь один раз — и тайтл в планах больше никогда не тянет из тебя очки'.tr),
                  _ExplainerLine(text: 'докупаешь ещё один слот в витрине наград на профиле'.tr),
                  _ExplainerLine(text: 'напоминаешь партнёру про план, который завис без движения'.tr),
                  const SizedBox(height: 16),
                  Text(
                    'здесь нет очков за количество записей, оценок или заметок — только за честные решения. но то, что накопилось, — не просто цифра: им можно распорядиться по-настоящему, прямо на этом экране и в общем дневнике.'.tr,
                    style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplainerLine extends StatelessWidget {
  final String text;
  const _ExplainerLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: SeenlyPalette.mustard, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text, style: SeenlyText.serif(size: 14)),
          ),
        ],
      ),
    );
  }
}

class _PrivacyRow extends StatefulWidget {
  final bool visible;
  const _PrivacyRow({required this.visible});

  @override
  State<_PrivacyRow> createState() => _PrivacyRowState();
}

class _PrivacyRowState extends State<_PrivacyRow> {
  late bool _visible = widget.visible;
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    final previous = _visible;
    setState(() {
      _visible = value;
      _saving = true;
    });
    try {
      await context.read<AppState>().sincerity.setVisibleToFriends(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _visible = previous);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'показывать друзьям'.tr,
                  style: SeenlyText.serif(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'по умолчанию видно только тебе'.tr,
                  style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                ),
              ],
            ),
          ),
          SoftSwap(
            alignment: Alignment.center,
            duration: const Duration(milliseconds: 200),
            child: _saving
                ? Padding(
                    key: const ValueKey<String>('saving'),
                    padding: const EdgeInsets.only(right: 6),
                    child: BouncingDots(color: SeenlyPalette.accent, dotSize: 4),
                  )
                : const SizedBox(key: ValueKey<String>('idle'), width: 1, height: 1),
          ),
          Switch.adaptive(
            value: _visible,
            activeColor: SeenlyPalette.accent,
            onChanged: _saving ? null : _toggle,
          ),
        ],
      ),
    );
  }
}

class _StaleItemsSection extends StatefulWidget {
  final List<SincerityStaleItem> items;
  final int balance;
  final VoidCallback onSettled;
  const _StaleItemsSection({required this.items, required this.balance, required this.onSettled});

  @override
  State<_StaleItemsSection> createState() => _StaleItemsSectionState();
}

class _StaleItemsSectionState extends State<_StaleItemsSection> {
  final Set<String> _settling = {};

  Future<void> _settle(SincerityStaleItem item) async {
    final confirmed = await SpendConfirmSheet.show(
      context,
      title: 'погасить долг?'.tr,
      body: '«${item.title}» слишком давно висит в планах без движения. заплати один раз — и это больше никогда не потянет из тебя очки.'.tr,
      cost: item.settleCost,
      balance: widget.balance,
      confirmLabel: 'погасить'.tr,
    );
    if (!confirmed || !mounted) return;
    setState(() => _settling.add(item.entryId));
    try {
      await context.read<AppState>().watchlist.settleDebt(item.entryId);
      if (!mounted) return;
      widget.onSettled();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _settling.remove(item.entryId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final unpaid = widget.items.where((i) => !i.debtExempt).toList();
    if (unpaid.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('копится долг'.tr, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'эти тайтлы слишком давно висят в планах без движения — можно погасить один раз и забыть'.tr,
            style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 14),
          for (final item in unpaid) ...[
            _StaleItemRow(
              item: item,
              busy: _settling.contains(item.entryId),
              onSettle: () => _settle(item),
            ),
            if (item != unpaid.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _StaleItemRow extends StatelessWidget {
  final SincerityStaleItem item;
  final bool busy;
  final VoidCallback onSettle;
  const _StaleItemRow({required this.item, required this.busy, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.posterUrl == null
              ? Container(width: 34, height: 48, color: SeenlyPalette.cork)
              : Image.network(
                  item.posterUrl!,
                  width: 34,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 34, height: 48, color: SeenlyPalette.cork),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: SeenlyText.serif(size: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${'в планах уже'.tr} ${nCount('nDays', item.ageDays)}',
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PressScale(
          onTap: busy ? null : onSettle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: busy
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: SeenlyPalette.accent),
                  )
                : Text(
                    '−${item.settleCost}',
                    style: SeenlyText.mono(size: 12, weight: FontWeight.w700, color: SeenlyPalette.accent),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PendingRecommendationsSection extends StatelessWidget {
  final RecommendationsResponse recs;
  const _PendingRecommendationsSection({required this.recs});

  @override
  Widget build(BuildContext context) {
    final pendingOut = recs.outgoing.where((r) => r.isPending).toList();
    final pendingIn = recs.incoming.where((r) => r.isPending).toList();
    if (pendingOut.isEmpty && pendingIn.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ставки в игре'.tr, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'решится само, как только друг оценит тайтл'.tr,
            style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 12),
          for (final r in pendingOut) ...[
            _PendingRecommendationRow(
              text: '${'ты поставил(а) на'.tr} ${r.recipientUsername} — ${r.title} (${r.predictedRating})',
              stake: r.stakedAmount,
            ),
            if (r != pendingOut.last || pendingIn.isNotEmpty) const SizedBox(height: 10),
          ],
          for (final r in pendingIn) ...[
            _PendingRecommendationRow(
              text: '${r.stakerUsername} ${'поставил(а) на тебя'.tr} — ${r.title} (${r.predictedRating})',
              stake: r.stakedAmount,
              isIncoming: true,
            ),
            if (r != pendingIn.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PendingRecommendationRow extends StatelessWidget {
  final String text;
  final int stake;
  final bool isIncoming;
  const _PendingRecommendationRow({required this.text, required this.stake, this.isIncoming = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          size: 13,
          color: SeenlyPalette.periwinkle,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: SeenlyText.serif(size: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(
          '${isIncoming ? '' : '−'}$stake',
          style: SeenlyText.mono(size: 12, weight: FontWeight.w700, color: SeenlyPalette.periwinkle),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Entrance(
      delay: const Duration(milliseconds: 260),
      riseBy: 10,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'здесь появится история, как только что-то честно закроется'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.emptyState(size: 14),
          ),
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final SincerityTransaction txn;
  const _TransactionRow({required this.txn});

  String _reasonLabel() {
    switch (txn.reason) {
      case 'closed_gestalt':
        return 'закрыл(а) давнее ожидание'.tr;
      case 'revised_rating':
        return 'изменил(а) старую оценку'.tr;
      case 'accurate_recommendation':
        return 'рекомендация попала в точку'.tr;
      case 'honest_drop':
        return 'честно бросил(а) с причиной'.tr;
      case 'second_chance':
        return 'дал(а) второй шанс — и досмотрел(а)'.tr;
      case 'formed_own_opinion':
        return 'оценил(а) сам(а), не подглядывая'.tr;
      case 'recommendation_stake':
        return 'ставка на рекомендацию'.tr;
      case 'stake_forfeited':
        return 'ставка не сыграла'.tr;
      case 'stake_expired':
        return 'ставка не сыграна — возвращена'.tr;
      case 'spoiler_unlock':
        return 'открыл(а) оценку партнёра пораньше'.tr;
      case 'debt_settled':
        return 'погасил(а) долг навсегда'.tr;
      case 'pin_slot_purchased':
        return 'купил(а) слот в витрине наград'.tr;
      case 'nudge_sent':
        return 'напомнил(а) о совместном плане'.tr;
      case 'stale_debt':
        return 'долг за забытое в планах'.tr;
      default:
        return txn.reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    final positive = txn.delta > 0;
    final zero = txn.delta == 0;
    final color = zero
        ? SeenlyPalette.inkFaint
        : positive
            ? SeenlyPalette.mustard
            : SeenlyPalette.inkMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              zero ? '·' : (positive ? '+${txn.delta}' : '${txn.delta}'),
              style: SeenlyText.serif(size: 14, weight: FontWeight.w600, color: color),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_reasonLabel(), style: SeenlyText.serif(size: 14)),
                if (txn.note != null && txn.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      txn.note!,
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Entrance(
        riseBy: 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: SeenlyText.serif(size: 14, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'повторить'.tr,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
