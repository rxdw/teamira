import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/profile_stats.dart';
import '../../models/saved_wrapped_period.dart';
import '../../services/custom_wrapped_service.dart';
import '../../services/partner_compare_service.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../theme/notebook_paper.dart';
import '../../widgets/polaroid_card.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';
import '../premium/saved_periods_screen.dart';
import '../../theme/clay_kit.dart';

/// Profile -> "статистика": the numbers-and-charts sibling of Wrapped's
/// card-by-card narrative (same WrappedSummary, same month/year/
/// all-time/"свой период" switch — see ProfileService.wrappedSummary
/// and, for a custom range, CustomWrappedService) — but built to open
/// with its own bit of drama rather than reading like a spreadsheet: a
/// poster-collage cover up top carries the headline numbers (counting
/// up rather than just appearing), related figures share a single card
/// instead of each getting its own identical box, and chart types vary
/// (bars, a split ribbon, a rank gauge, a donut) instead of repeating
/// the same little circle five times. Every figure here is still real —
/// nothing illustrative, same as before.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

/// [StatsScreen]'s combined fetch result — same reasoning as
/// WrappedScreen's own _WrappedLoad: bundling the partner comparison in
/// here rather than a second independent FutureBuilder, so it can slot
/// into `sections` alongside everything else that's conditionally
/// included based on real data.
class _StatsLoad {
  final WrappedSummary summary;
  final PartnerCompareData? partnerCompare;
  final List<_TrendPoint>? trend;
  const _StatsLoad(this.summary, this.partnerCompare, this.trend);
}

/// One month's totals for _TrendCard — see
/// _StatsScreenState._loadTrend for how this gets built.
class _TrendPoint {
  final int year;
  final int month;
  final int count;
  final double hours;
  const _TrendPoint({required this.year, required this.month, required this.count, required this.hours});
}

class _StatsScreenState extends State<StatsScreen> {
  String _scope = 'year';
  String? _customTitle;
  DateTimeRange? _customRange;
  late Future<_StatsLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StatsLoad> _load() async {
    final summary = await _loadSummary();
    final compare = await _loadPartnerCompare();
    final trend = await _loadTrend();
    return _StatsLoad(summary, compare, trend);
  }

  /// The last up-to-12 months with any real activity, oldest first —
  /// powers _TrendCard's bar chart. Free accounts still get this
  /// fetched (it's cheap — WrappedPeriods is just a list of which
  /// months have data, not the data itself) so the card can still be
  /// shown as a locked teaser rather than silently omitted; the
  /// per-month totals underneath (the actual N extra fetches) only
  /// happen for premium. Returns null when there isn't enough history
  /// for a trend to mean anything (fewer than 2 months) or the fetch
  /// failed — never blocks the rest of the stats either way.
  Future<List<_TrendPoint>?> _loadTrend() async {
    try {
      final app = context.read<AppState>();
      final isPremium = context.read<PremiumService>().isPremium;
      final periods = await app.profile.wrappedPeriods();
      final months = [...periods.months]
        ..sort((a, b) => a.year != b.year ? a.year.compareTo(b.year) : a.month.compareTo(b.month));
      if (months.length < 2) return null;
      final recent = months.length > 12 ? months.sublist(months.length - 12) : months;
      if (!isPremium) {
        // Locked teaser only needs to know a trend *exists* — the
        // per-month numbers themselves stay behind premium, so this
        // skips the N extra fetches entirely for free accounts.
        return [for (final m in recent) _TrendPoint(year: m.year, month: m.month, count: 0, hours: 0)];
      }
      final summaries = await Future.wait(recent.map(
        (m) => app.profile.wrappedSummary(scope: 'month', year: m.year, month: m.month),
      ));
      return [
        for (var i = 0; i < recent.length; i++)
          _TrendPoint(
            year: recent[i].year,
            month: recent[i].month,
            count: summaries[i].totalLogged,
            hours: summaries[i].totalHours,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Same "no matching backend endpoint, so compute it locally" shape
  /// as WrappedScreen's own _loadSummary — see CustomWrappedService's
  /// docstring for why.
  Future<WrappedSummary> _loadSummary() async {
    final title = _customTitle;
    final range = _customRange;
    if (_scope == 'custom' && title != null && range != null) {
      final entries = await context.read<AppState>().diary.list();
      return CustomWrappedService.build(title: title, range: range, allEntries: entries);
    }
    return context.read<AppState>().profile.wrappedSummary(scope: _scope);
  }

  /// Same fetch WrappedScreen's own PartnerCompareCard uses (see its
  /// doc comment) — null whenever there's nothing to compare (not
  /// linked, or the fetch failed), which is fine here too since it
  /// never blocks the stats themselves from loading.
  Future<PartnerCompareData?> _loadPartnerCompare() async {
    try {
      final app = context.read<AppState>();
      final status = await app.partner.status();
      if (!status.linked || status.members.length < 2) return null;
      final list = await app.partner.coViewing();
      return PartnerCompareService.build(
        myUsername: list.myUsername,
        otherUsernames: list.otherUsernames,
        watched: list.watched,
        planned: list.planned,
      );
    } catch (_) {
      return null;
    }
  }

  void _switchTo(String scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _customTitle = null;
      _customRange = null;
      _future = _load();
    });
  }

  void _switchToCustom(SavedWrappedPeriod period) {
    setState(() {
      _scope = 'custom';
      _customTitle = period.title;
      _customRange = period.range;
      _future = _load();
    });
  }

  /// Same premium gate every other "свой период" doorway uses (see
  /// PeriodPickerSheet's own row in wrapped_screen.dart) — checked here
  /// too since this is a separate entry point into
  /// [SavedPeriodsScreen], not reachable through that sheet.
  Future<void> _openCustomPeriodPicker() async {
    final isPremium = context.read<PremiumService>().isPremium;
    if (!isPremium) {
      await showPremiumUpsellSheet(
        context,
        triggerSource: 'custom_wrapped',
        icon: Icons.calendar_month_outlined,
        title: 'свой итог — премиум-функция'.tr,
        message: 'назови любой период — поездку, сезон, отношения — и получи полноценный итог по нему'.tr,
      );
      return;
    }
    final period = await Navigator.of(context)
        .push<SavedWrappedPeriod>(MaterialPageRoute(builder: (_) => const SavedPeriodsScreen()));
    if (period == null || !mounted) return;
    _switchToCustom(period);
  }

  // Same soft cross-fade ProfileScreen uses between its skeleton/error/
  // content states, so switching scope here doesn't hard-cut the page.
  Widget _fadeSwitch(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 2),
                  Text('статистика'.tr, style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: _ScopeSwitcher(scope: _scope, onChanged: _switchTo)),
                  const SizedBox(width: 8),
                  _CustomPeriodButton(active: _scope == 'custom', onTap: _openCustomPeriodPicker),
                ],
              ),
            ),
            if (_scope == 'custom' && _customTitle != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  _customTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<_StatsLoad>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData && !snapshot.hasError) {
                    return _fadeSwitch(
                      const Center(key: ValueKey('stats-loading'), child: _StatsSkeleton()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _fadeSwitch(
                      Center(
                        key: const ValueKey('stats-error'),
                        child: Text('не получилось загрузить статистику'.tr,
                            style: SeenlyText.serif(color: SeenlyPalette.inkMuted)),
                      ),
                    );
                  }
                  final s = snapshot.data!.summary;
                  final partnerCompare = snapshot.data!.partnerCompare;
                  final trend = snapshot.data!.trend;
                  if (s.totalLogged == 0) {
                    return _fadeSwitch(
                      Center(
                        key: ValueKey('stats-empty-${s.scope}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                              LocaleService.appIsRussian
                                  ? 'за ${s.periodLabel} в дневнике пока пусто'
                                  : 'the diary is still empty for ${s.periodLabel}',
                              textAlign: TextAlign.center,
                              style: SeenlyText.serif(color: SeenlyPalette.inkMuted)),
                        ),
                      ),
                    );
                  }

                  // Claims one stagger slot per top-level section — same
                  // capped cascade ProfileScreen's own `nextReveal` uses,
                  // so a scope switch replays the whole cascade rather
                  // than the cards just silently swapping numbers.
                  var revealSlot = 0;
                  Duration nextReveal({int step = 55, int maxSlots = 8}) {
                    final slot = revealSlot < maxSlots ? revealSlot : maxSlots;
                    final d = Duration(milliseconds: slot * step);
                    revealSlot++;
                    return d;
                  }

                  // Every section flows through here in one list so
                  // ordering stays a single source of truth.
                  final sections = <Widget>[
                    _HeroCover(summary: s),
                    _ActivityCard(summary: s),
                    if (trend != null) _TrendCard(trend: trend),
                    _RhythmCard(summary: s),
                    if (s.hoursPercentile != null) _PercentileCard(summary: s),
                    if (s.genreMix.isNotEmpty) _GenreCard(summary: s),
                    if (s.decades.isNotEmpty) _DecadeCard(summary: s),
                    _WatchStyleCard(summary: s),
                    if (partnerCompare != null) _PartnerCompareStatsCard(compare: partnerCompare),
                    if (s.ratingHistogram.any((b) => b.count > 0)) _RatingsCard(summary: s),
                    if (s.topDirectors.isNotEmpty)
                      _TopListCard(
                        title: 'режиссёры'.tr,
                        items: [for (final d in s.topDirectors) (d.name, d.count)],
                      ),
                    if (s.favoriteReview != null) _FavoriteReviewCard(summary: s),
                    if (s.receiptItems.isNotEmpty)
                      _TopListCard(
                        title: 'чаще всего пересматривала'.tr,
                        items: [
                          for (final r in s.receiptItems.take(5))
                            if (r.count > 1) (r.title, r.count),
                        ],
                        emptyText: 'пока без повторов'.tr,
                      ),
                    if (s.first != null && s.last != null) _BookendsCard(summary: s),
                  ];

                  return _fadeSwitch(
                    ListView.separated(
                      key: ValueKey('stats-${s.scope}'),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                      itemCount: sections.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, i) =>
                          Entrance(delay: nextReveal(), child: sections[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — a hint of the hero + a couple of cards, in the app's
// own shimmer, rather than a bare spinner.
// ---------------------------------------------------------------------------

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        children: [
          ShimmerBlock(width: double.infinity, height: 210, borderRadius: BorderRadius.circular(24)),
          const SizedBox(height: 16),
          ShimmerBlock(width: double.infinity, height: 150, borderRadius: BorderRadius.circular(20)),
          const SizedBox(height: 16),
          ShimmerBlock(width: double.infinity, height: 150, borderRadius: BorderRadius.circular(20)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scope switcher
// ---------------------------------------------------------------------------

/// The small round "свой период" doorway next to _ScopeSwitcher — same
/// gate as PeriodPickerSheet's own row (see
/// _StatsScreenState._openCustomPeriodPicker), just a separate entry
/// point since Stats' scope switcher is a plain 3-way toggle rather
/// than a full picker sheet.
class _CustomPeriodButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _CustomPeriodButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? SeenlyPalette.accent : SeenlyPalette.cork,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.calendar_month_outlined, size: 17,
            color: active ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkFaint),
      ),
    );
  }
}

class _ScopeSwitcher extends StatelessWidget {
  final String scope;
  final ValueChanged<String> onChanged;
  const _ScopeSwitcher({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: SeenlyPalette.cork, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _segment('месяц'.tr, 'month'),
          _segment('год'.tr, 'year'),
          _segment('всё время'.tr, 'all'),
        ],
      ),
    );
  }

  Widget _segment(String label, String value) {
    final active = value == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: ClayBoxDecoration(
            color: active ? SeenlyPalette.paper : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? SeenlyPalette.softShadow : null,
          ),
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(
                size: 12,
                color: active ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
                weight: active ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared cozy card shell
// ---------------------------------------------------------------------------

class _DashCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _DashCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  final String? caption;
  const _CardTitle(this.text, {this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: SeenlyText.sectionTitle),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

/// The small uppercase caption used on the hero cover — same voice as
/// Wrapped's own `_Eyebrow`, kept local here since that one's private to
/// wrapped_screen.dart.
class _Eyebrow extends StatelessWidget {
  final String text;
  Color get color => _color ?? SeenlyPalette.inkFaint;
  final Color? _color;
  _Eyebrow(this.text, {Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SeenlyText.mono(size: 12, color: color, weight: FontWeight.w600),
      );
}

// ---------------------------------------------------------------------------
// Hero cover — one bold opening panel instead of three flat tiles: the
// period's own posters as a dimmed backdrop, the headline number large
// and counting up, the archetype worn as a little badge rather than
// boxed off on its own.
// ---------------------------------------------------------------------------

class _HeroCover extends StatelessWidget {
  final WrappedSummary summary;
  const _HeroCover({required this.summary});

  @override
  Widget build(BuildContext context) {
    final posters = summary.posterUrls;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SeenlyPalette.accent,
                    Color.lerp(SeenlyPalette.accent, SeenlyPalette.coral, 0.4)!,
                  ],
                ),
              ),
            ),
          ),
          if (posters.isNotEmpty) Positioned.fill(child: _PosterCollage(urls: posters)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SeenlyPalette.accent.withOpacity(0.42),
                    SeenlyPalette.accent.withOpacity(0.88),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Eyebrow(
                        summary.rangeLabel.isNotEmpty ? summary.rangeLabel : summary.periodLabel,
                        color: SeenlyPalette.accentOnAccent.withOpacity(0.85),
                      ),
                    ),
                    if (summary.archetypeLabel.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accentOnAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          summary.archetypeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.serif(
                            italic: true,
                            size: 12,
                            weight: FontWeight.w600,
                            color: SeenlyPalette.accentOnAccent,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CountUpNumber(
                      value: summary.totalHours,
                      decimals: 0,
                      duration: const Duration(milliseconds: 1000),
                      style: SeenlyText.serif(
                          size: 60, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                    ),
                    const SizedBox(width: 8),
                    Text('ч'.tr,
                        style: SeenlyText.serif(
                            size: 22, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent.withOpacity(0.85))),
                  ],
                ),
                const SizedBox(height: 2),
                Text('в дневнике'.tr,
                    style: SeenlyText.mono(size: 13, color: SeenlyPalette.accentOnAccent.withOpacity(0.82))),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _HeroMiniStat(
                      icon: Icons.local_movies_outlined,
                      value: summary.totalLogged.toDouble(),
                      label: 'сеансов'.tr,
                    ),
                    Container(
                      width: 1,
                      height: 30,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: SeenlyPalette.accentOnAccent.withOpacity(0.25),
                    ),
                    _HeroMiniStat(
                      icon: Icons.local_fire_department_outlined,
                      value: summary.longestStreakDays.toDouble(),
                      label: 'дней подряд'.tr,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  final IconData icon;
  final double value;
  final String label;
  const _HeroMiniStat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
        const SizedBox(width: 7),
        CountUpNumber(
          value: value,
          decimals: 0,
          duration: const Duration(milliseconds: 900),
          style: SeenlyText.serif(size: 16, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
        ),
        const SizedBox(width: 5),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.accentOnAccent.withOpacity(0.8))),
      ],
    );
  }
}

/// A dimmed filmstrip of the period's own posters, side by side and
/// slightly zoomed — pure texture behind the scrim above, never legible
/// enough to compete with the numbers on top of it.
class _PosterCollage extends StatelessWidget {
  final List<String> urls;
  const _PosterCollage({required this.urls});

  @override
  Widget build(BuildContext context) {
    final shown = urls.take(6).toList();
    return Opacity(
      opacity: 0.4,
      child: Row(
        children: [
          for (final url in shown)
            Expanded(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity (timeline) card
// ---------------------------------------------------------------------------

class _ActivityCard extends StatelessWidget {
  final WrappedSummary summary;
  const _ActivityCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final buckets = summary.timeline;
    final maxCount = buckets.isEmpty ? 0 : buckets.map((b) => b.count).reduce(math.max);
    final peakIndex = maxCount == 0 ? -1 : buckets.indexWhere((b) => b.count == maxCount);
    final isMonth = summary.scope == 'month';
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'активность'.tr,
            caption: summary.busiestTimelineLabel != null
                ? (LocaleService.appIsRussian
                    ? (isMonth ? 'самый плотный день — ${summary.busiestTimelineLabel}' : 'самый активный — ${summary.busiestTimelineLabel}')
                    : (isMonth ? 'busiest day — ${summary.busiestTimelineLabel}' : 'most active — ${summary.busiestTimelineLabel}'))
                : null,
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 92,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (peakIndex >= 0 && buckets.length > 1)
                  Align(
                    alignment: Alignment(
                      (2 * (peakIndex + 0.5) / buckets.length) - 1,
                      -1,
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                    ),
                  ),
                Positioned.fill(
                  top: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final b in buckets)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isMonth ? 0.8 : 2.5),
                            child: Tooltip(
                              message: '${b.label}: ${b.count}',
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                height: maxCount == 0 ? 3 : (4 + (b.count / maxCount) * 68),
                                decoration: BoxDecoration(
                                  gradient: b.count == 0
                                      ? null
                                      : LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: b.count == maxCount
                                              ? [SeenlyPalette.accent, SeenlyPalette.accent.withOpacity(0.75)]
                                              : [SeenlyPalette.tapeRose, SeenlyPalette.tapeRose.withOpacity(0.7)],
                                        ),
                                  color: b.count == 0 ? SeenlyPalette.background : null,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isMonth) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Center(
                      child: Text(b.label,
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rhythm card — weekday bars + peak-hour dial, one designed unit instead
// of two separate boxes that never quite lined up.
// ---------------------------------------------------------------------------

class _RhythmCard extends StatelessWidget {
  final WrappedSummary summary;
  const _RhythmCard({required this.summary});

  static final _labels = ['пн'.tr, 'вт'.tr, 'ср'.tr, 'чт'.tr, 'пт'.tr, 'сб'.tr, 'вс'.tr];

  @override
  Widget build(BuildContext context) {
    final weekdays = summary.weekdays;
    final maxCount = weekdays.isEmpty ? 0 : weekdays.map((d) => d.count).reduce(math.max);
    final hour = summary.peakHour;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('ритм недели'.tr,
              caption: LocaleService.appIsRussian
                  ? '${summary.weekendPercent.round()}% сеансов на выходных'
                  : '${summary.weekendPercent.round()}% of sessions on weekends'),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 54,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (int i = 0; i < weekdays.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Container(
                                    height: maxCount == 0 ? 3 : (4 + (weekdays[i].count / maxCount) * 46),
                                    decoration: BoxDecoration(
                                      color: (i == 5 || i == 6) ? SeenlyPalette.accent : SeenlyPalette.tapeSage,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          for (final l in _labels)
                            Expanded(
                              child: Center(
                                child: Text(l,
                                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: SeenlyPalette.border,
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(72, 72),
                              painter: _ArcPainter(
                                values: [summary.peakHourPercent / 100],
                                colors: [SeenlyPalette.accent],
                                backgroundColor: SeenlyPalette.cork,
                                strokeWidth: 9,
                              ),
                            ),
                            Text(
                              hour != null ? '${hour.toString().padLeft(2, '0')}:00' : '—',
                              style: SeenlyText.serif(size: 13.5, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('твой час'.tr,
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                    ],
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

// ---------------------------------------------------------------------------
// Percentile card — a rank gauge instead of another donut.
// ---------------------------------------------------------------------------

class _PercentileCard extends StatelessWidget {
  final WrappedSummary summary;
  const _PercentileCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final pct = summary.hoursPercentile!;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text('среди других зрителей'.tr, style: SeenlyText.sectionTitle)),
              CountUpNumber(
                value: pct.toDouble(),
                decimals: 0,
                suffix: '%',
                style: SeenlyText.serif(size: 22, weight: FontWeight.w700, color: SeenlyPalette.accent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RankGauge(percent: pct),
          const SizedBox(height: 10),
          Text(
            LocaleService.appIsRussian
                ? 'смотришь активнее, чем $pct% пользователей за ${summary.periodLabel}'
                : 'watching more actively than $pct% of users for ${summary.periodLabel}',
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RankGauge extends StatelessWidget {
  final int percent;
  const _RankGauge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final t = (percent / 100).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: t),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animT, _) {
        return SizedBox(
          height: 22,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(height: 10, color: SeenlyPalette.cork),
              ),
              FractionallySizedBox(
                widthFactor: animT,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(height: 10, color: SeenlyPalette.accent),
                ),
              ),
              Align(
                alignment: Alignment(animT * 2 - 1, 0),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: ClayBoxDecoration(
                    color: SeenlyPalette.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: SeenlyPalette.accent, width: 3),
                    boxShadow: SeenlyPalette.softShadow,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Genre donut card
// ---------------------------------------------------------------------------

class _GenreCard extends StatelessWidget {
  final WrappedSummary summary;
  const _GenreCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final mix = summary.genreMix;
    return _DashCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(100, 100),
                  painter: _ArcPainter(
                    values: [for (final g in mix) g.percent / 100],
                    colors: [for (int i = 0; i < mix.length; i++) SeenlyPalette.gridColorFor(i)],
                    strokeWidth: 17,
                    gapDegrees: 2,
                  ),
                ),
                if (mix.isNotEmpty)
                  Text('${mix.first.percent.round()}%',
                      style: SeenlyText.serif(size: 15, weight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('жанры'.tr, style: SeenlyText.sectionTitle),
                const SizedBox(height: 10),
                for (int i = 0; i < mix.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: SeenlyPalette.gridColorFor(i), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(mix[i].genre,
                              style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        Text('${mix[i].percent.round()}%', style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                      ],
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

// ---------------------------------------------------------------------------
// Decade card
// ---------------------------------------------------------------------------

class _DecadeCard extends StatelessWidget {
  final WrappedSummary summary;
  const _DecadeCard({required this.summary});

  static final _labelRu = {'2020s': '2020-е'.tr, '2010s': '2010-е'.tr, 'older': 'до 2010-х'.tr};

  @override
  Widget build(BuildContext context) {
    final decades = summary.decades;
    final maxPercent = decades.fold(0.0, (m, d) => d.percent > m ? d.percent : m);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('из какого времени фильмы'.tr),
          const SizedBox(height: 18),
          for (int i = 0; i < decades.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == decades.length - 1 ? 0 : 10),
              child: _EraShelfRow(
                label: _labelRu[decades[i].label] ?? decades[i].label,
                count: decades[i].count,
                percent: decades[i].percent,
                fillFraction: maxPercent <= 0 ? 0.16 : (decades[i].percent / maxPercent).clamp(0.16, 1.0),
                isLast: i == decades.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of a compact "shelf" timeline for the decade breakdown — a
/// spine dot connected by a line to the next row, and a card whose
/// height and bottom fill bar both scale with that decade's share of
/// the pool. Reused from the era-picker on the "cant decide" flow
/// (see decide_filters_screen.dart's _EraTimeline/_EraRow), trimmed
/// down to a static read-only version sized for a stats card instead
/// of a full-screen picker: fixed row heights instead of stretching to
/// fill the screen, and no selection state or tap handling.
class _EraShelfRow extends StatelessWidget {
  final String label;
  final int count;
  final double percent;
  final double fillFraction;
  final bool isLast;

  const _EraShelfRow({
    required this.label,
    required this.count,
    required this.percent,
    required this.fillFraction,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    // 70 is the floor a row needs to fit its content (label line plus the
    // two-line percent/count stack with its padding) without overflowing
    // even at the smallest fillFraction — the row only grows taller than
    // that as its share of the pool grows.
    final height = 70.0 + 20.0 * fillFraction;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.accent),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 1.5, color: SeenlyPalette.dashedBorder)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: SeenlyPalette.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SeenlyPalette.border),
              ),
              child: Stack(
                children: [
                  // A proportional fill along the bottom — the bigger
                  // this decade's slice of the pool, the further it
                  // reaches, echoing the era-picker's fill bar.
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                      widthFactor: fillFraction,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent.withOpacity(0.3),
                          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(label,
                              style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.ink)),
                          const Spacer(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${percent.round()}%',
                                  style: SeenlyText.serif(
                                      size: 26, weight: FontWeight.w700, color: SeenlyPalette.accent.withOpacity(0.55))),
                              const SizedBox(height: 2),
                              Text(
                                nCount('nMovies', count).toUpperCase(),
                                style: SeenlyText.mono(size: 10, weight: FontWeight.w600, color: SeenlyPalette.inkMuted)
                                    .copyWith(letterSpacing: 1.0),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Watch-style card — solo/company and new/rewatch as split ribbons in one
// card instead of two separate donut boxes that said less at a glance.
// ---------------------------------------------------------------------------

class _WatchStyleCard extends StatelessWidget {
  final WrappedSummary summary;
  const _WatchStyleCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final showNewRewatch = summary.newCount + summary.rewatchCount > 0;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('как ты смотрела'.tr),
          const SizedBox(height: 16),
          _SplitRibbon(
            leftLabel: 'в одиночку'.tr,
            leftValue: summary.soloCount,
            leftColor: SeenlyPalette.accent,
            rightLabel: 'с кем-то'.tr,
            rightValue: summary.companyCount,
            rightColor: SeenlyPalette.cork,
          ),
          if (showNewRewatch) ...[
            const SizedBox(height: 16),
            _SplitRibbon(
              leftLabel: 'впервые'.tr,
              leftValue: summary.newCount,
              leftColor: SeenlyPalette.periwinkle,
              rightLabel: 'пересмотр'.tr,
              rightValue: summary.rewatchCount,
              rightColor: SeenlyPalette.cork,
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitRibbon extends StatelessWidget {
  final String leftLabel;
  final int leftValue;
  final Color leftColor;
  final String rightLabel;
  final int rightValue;
  final Color rightColor;
  const _SplitRibbon({
    required this.leftLabel,
    required this.leftValue,
    required this.leftColor,
    required this.rightLabel,
    required this.rightValue,
    required this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    final total = leftValue + rightValue;
    final leftFlex = total == 0 ? 1 : (leftValue * 1000 / total).round().clamp(1, 999);
    final rightFlex = total == 0 ? 1 : (1000 - leftFlex).clamp(1, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                Expanded(flex: leftFlex, child: Container(color: leftColor)),
                Expanded(flex: rightFlex, child: Container(color: rightColor)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: leftColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text('$leftLabel · $leftValue',
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Spacer(),
            Flexible(
              child: Text('$rightValue · $rightLabel',
                  textAlign: TextAlign.right,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: rightColor, shape: BoxShape.circle)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Partner compare — premium
// ---------------------------------------------------------------------------

/// Only ever included in `sections` when there's actually a partner to
/// compare with (see _StatsScreenState._loadPartnerCompare) — free
/// accounts still get the card, just as a locked teaser rather than
/// real numbers, same split as WrappedScreen's own PartnerCompareCard
/// (see wrapped_screen.dart — this is a separate widget, not a shared
/// one, since the two screens' card shells don't share a base).
class _PartnerCompareStatsCard extends StatelessWidget {
  final PartnerCompareData compare;
  const _PartnerCompareStatsCard({required this.compare});

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    final isCompany = compare.others.length > 1;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'кто выбирает?'.tr,
            caption: isCompany ? 'ваш круг'.tr : 'вы вдвоём'.tr,
          ),
          const SizedBox(height: 16),
          if (isPremium)
            _PartnerCompareStatsReveal(compare: compare)
          else
            _PartnerCompareStatsLocked(isCompany: isCompany),
        ],
      ),
    );
  }
}

class _PartnerCompareStatsReveal extends StatelessWidget {
  final PartnerCompareData compare;
  const _PartnerCompareStatsReveal({required this.compare});

  @override
  Widget build(BuildContext context) {
    final total = compare.people.fold<int>(0, (sum, p) => sum + p.suggestedCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in compare.people) ...[
          _StatsCompareBar(
            label: p.isSelf ? (LocaleService.appIsRussian ? 'ты' : 'you') : p.username,
            value: p.suggestedCount,
            total: total,
            strong: p.isSelf,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        Text(
          LocaleService.appIsRussian
              ? '${compare.watchedTogetherCount} посмотрено вместе · ${compare.plannedCount} в планах'
              : '${compare.watchedTogetherCount} watched together · ${compare.plannedCount} planned',
          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
        ),
      ],
    );
  }
}

class _StatsCompareBar extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final bool strong;
  const _StatsCompareBar({required this.label, required this.value, required this.total, required this.strong});

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : value / total;
    final color = strong ? SeenlyPalette.accent : SeenlyPalette.periwinkle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink,
                      weight: strong ? FontWeight.w700 : FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('$value', style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                Container(color: SeenlyPalette.cork),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.03, 1.0),
                  child: Container(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PartnerCompareStatsLocked extends StatelessWidget {
  final bool isCompany;
  const _PartnerCompareStatsLocked({required this.isCompany});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 18, color: SeenlyPalette.inkFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            LocaleService.appIsRussian
                ? (isCompany ? 'кто в круге предлагает больше' : 'кто из вас двоих предлагает больше')
                : (isCompany ? 'who in the circle picks more' : 'who between you two picks more'),
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => showPremiumUpsellSheet(
            context,
            triggerSource: 'circle_stats',
            icon: Icons.people_outline,
            title: 'you vs your circle is premium'.tr,
            message: 'see who suggests more of what you watch together — premium unlocks the numbers'.tr,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('open'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trend card — premium
// ---------------------------------------------------------------------------

const _trendMonthNamesRu = ['', 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
const _trendMonthNamesEn = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Only ever included in `sections` when there are at least two months
/// of real history to compare (see _StatsScreenState._loadTrend) — a
/// trend needs at least two points, and one lonely bar wouldn't say
/// much anyway. Free accounts still get the card, just as a locked
/// teaser with the month labels but none of the real numbers, same
/// split as every other premium card on this screen.
class _TrendCard extends StatelessWidget {
  final List<_TrendPoint> trend;
  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'твоя динамика'.tr,
            caption: LocaleService.appIsRussian
                ? 'последние ${trend.length} мес.'
                : 'last ${trend.length} months',
          ),
          const SizedBox(height: 18),
          if (isPremium) _TrendChart(trend: trend) else _TrendLocked(months: trend.length),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_TrendPoint> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    final maxCount = trend.map((p) => p.count).fold(0, (a, b) => a > b ? a : b);
    final names = LocaleService.appIsRussian ? _trendMonthNamesRu : _trendMonthNamesEn;
    final last = trend.last;
    final prev = trend.length > 1 ? trend[trend.length - 2] : null;
    String? deltaLabel;
    if (prev != null && prev.count > 0) {
      final delta = ((last.count - prev.count) / prev.count * 100).round();
      if (delta != 0) {
        final sign = delta > 0 ? '+' : '';
        deltaLabel = LocaleService.appIsRussian
            ? '$sign$delta% к прошлому месяцу'
            : '$sign$delta% vs last month';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < trend.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(trend[i].count > 0 ? '${trend[i].count}' : '',
                            style: SeenlyText.mono(size: 8, color: SeenlyPalette.inkFaint)),
                        const SizedBox(height: 4),
                        Container(
                          height: maxCount == 0
                              ? 4
                              : 6 + (trend[i].count / maxCount) * 70,
                          decoration: BoxDecoration(
                            color: i == trend.length - 1 ? SeenlyPalette.accent : SeenlyPalette.periwinkle.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(names[trend[i].month],
                            style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (deltaLabel != null) ...[
          const SizedBox(height: 12),
          Text(deltaLabel, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
        ],
      ],
    );
  }
}

class _TrendLocked extends StatelessWidget {
  final int months;
  const _TrendLocked({required this.months});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.show_chart, size: 18, color: SeenlyPalette.inkFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            LocaleService.appIsRussian
                ? 'как менялась активность за $months мес.'
                : 'how activity changed over $months months',
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => showPremiumUpsellSheet(
            context,
            triggerSource: 'trend_chart',
            icon: Icons.show_chart,
            title: 'your trend is premium'.tr,
            message: 'see month by month how much you\'re watching, not just one period at a time — premium unlocks the chart'.tr,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('open'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ratings card
// ---------------------------------------------------------------------------

class _RatingsCard extends StatelessWidget {
  final WrappedSummary summary;
  const _RatingsCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final buckets = summary.ratingHistogram;
    final maxCount = buckets.isEmpty ? 0 : buckets.map((b) => b.count).reduce(math.max);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CountUpNumber(
                value: summary.averageRating,
                decimals: 1,
                style: SeenlyText.serif(size: 28, weight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                      LocaleService.appIsRussian
                          ? 'средняя оценка · ${summary.reviewCount} ${nOnly('nReviews', summary.reviewCount)}'
                          : 'average rating · ${summary.reviewCount} ${summary.reviewCount == 1 ? 'review' : 'reviews'}',
                      style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (summary.fullMarksCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star, size: 12, color: SeenlyPalette.mustard),
                const SizedBox(width: 6),
                Text(
                    LocaleService.appIsRussian
                        ? '${summary.fullMarksCount} на полную десятку'
                        : '${summary.fullMarksCount} perfect ${summary.fullMarksCount == 1 ? 'ten' : 'tens'}',
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Tooltip(
                        message: '${b.rating}/10: ${b.count}',
                        child: Container(
                          height: maxCount == 0 ? 3 : (4 + (b.count / maxCount) * 52),
                          decoration: BoxDecoration(
                            color: b.count == 0 ? SeenlyPalette.background : SeenlyPalette.ratingColor(b.rating),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('1'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder)),
              const Spacer(),
              Text('10'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top list card (directors / most rewatched)
// ---------------------------------------------------------------------------

class _TopListCard extends StatelessWidget {
  final String title;
  final List<(String, int)> items;
  final String? emptyText;
  const _TopListCard({required this.title, required this.items, this.emptyText});

  @override
  Widget build(BuildContext context) {
    final maxCount = items.isEmpty ? 0 : items.map((e) => e.$2).reduce(math.max);
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Text(emptyText ?? 'пока нет данных'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder))
          else
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 22, height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0 ? SeenlyPalette.accent.withOpacity(0.16) : SeenlyPalette.background,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: SeenlyText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: i == 0 ? SeenlyPalette.accent : SeenlyPalette.inkFaint)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(items[i].$1,
                                    style: SeenlyText.bodyText, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              Text('${items[i].$2}×', style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: RuledProgressBar(
                              value: maxCount == 0 ? 0 : items[i].$2 / maxCount,
                              minHeight: 5,
                              backgroundColor: SeenlyPalette.background,
                              valueColor: SeenlyPalette.accent,
                            ),
                          ),
                        ],
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

// ---------------------------------------------------------------------------
// Favorite review card — restyled around the app's own signature scrapbook
// element (PolaroidCard) instead of a plain rounded-rect thumbnail.
// ---------------------------------------------------------------------------

class _FavoriteReviewCard extends StatelessWidget {
  final WrappedSummary summary;
  const _FavoriteReviewCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final review = summary.favoriteReview!;
    final hasNote = review.note != null && review.note!.trim().isNotEmpty;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('любимая рецензия периода'.tr),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PolaroidCard(
                posterUrl: review.posterUrl,
                caption: review.rating != null ? '${review.rating}/10' : review.title,
                fallbackColor: SeenlyPalette.accent,
                size: 66,
                rotationTurns: -0.025,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.title,
                        style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    if (review.dateLabel != null)
                      Text(review.dateLabel!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                    if (hasNote) ...[
                      const SizedBox(height: 10),
                      Text('«${review.note!.trim()}»',
                          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                          maxLines: 4, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookends card (first & last logged this period) — a small connected
// timeline with real posters instead of two plain text columns.
// ---------------------------------------------------------------------------

class _BookendsCard extends StatelessWidget {
  final WrappedSummary summary;
  const _BookendsCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final first = summary.first!;
    final last = summary.last!;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('первое и последнее'.tr),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _Bookend(moment: first)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.east, size: 16, color: SeenlyPalette.accent),
                  if (summary.daysSpan > 0) ...[
                    const SizedBox(height: 6),
                    Text('${summary.daysSpan}',
                        style: SeenlyText.serif(size: 16, weight: FontWeight.w700, color: SeenlyPalette.accent)),
                    Text(_daysWord(summary.daysSpan),
                        style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                  ],
                ],
              ),
              Expanded(child: _Bookend(moment: last, alignEnd: true)),
            ],
          ),
        ],
      ),
    );
  }

  static String _daysWord(int n) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return 'дней'.tr;
    if (mod10 == 1) return 'день'.tr;
    if (mod10 >= 2 && mod10 <= 4) return 'дня'.tr;
    return 'дней'.tr;
  }
}

class _Bookend extends StatelessWidget {
  final WrappedTitleMoment moment;
  final bool alignEnd;
  const _Bookend({required this.moment, this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 44,
        height: 62,
        child: moment.posterUrl != null && moment.posterUrl!.isNotEmpty
            ? FadeInNetworkImage(
                url: moment.posterUrl!,
                placeholder: Container(color: SeenlyPalette.cork),
              )
            : Container(
                color: SeenlyPalette.cork,
                child: Icon(Icons.local_movies_outlined, size: 16, color: SeenlyPalette.inkFaint),
              ),
      ),
    );
    final text = Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(moment.dateLabel, style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
        const SizedBox(height: 4),
        Text(moment.title,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    );
    final row = alignEnd
        ? [Expanded(child: text), const SizedBox(width: 10), poster]
        : [poster, const SizedBox(width: 10), Expanded(child: text)];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: row);
  }
}

// ---------------------------------------------------------------------------
// Shared arc painter (donut/clock charts)
// ---------------------------------------------------------------------------

class _ArcPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  Color get backgroundColor => _backgroundColor ?? SeenlyPalette.background;
  final Color? _backgroundColor;
  final double strokeWidth;
  final double gapDegrees;

  _ArcPainter({
    required this.values,
    required this.colors,
    Color? backgroundColor,
    this.strokeWidth = 12,
    this.gapDegrees = 0,
  }) : _backgroundColor = backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gap = gapDegrees * math.pi / 180;

    final track = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = values[i].clamp(0.0, 1.0) * 2 * math.pi;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = values.length > 1 ? StrokeCap.butt : StrokeCap.round;
      final drawSweep = values.length > 1 ? math.max(sweep - gap, 0.001) : sweep;
      canvas.drawArc(rect, start, drawSweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
