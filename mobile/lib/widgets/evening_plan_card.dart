import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/planned_evening.dart';
import '../services/evening_plan_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'plan_evening_sheet.dart';
import 'themed_loading_indicator.dart';
import '../screens/title/title_detail_screen.dart';

/// The "plan an evening" feature's one piece of UI, dropped onto three
/// screens (Home, Profile, CoViewingScreen) — reads the single shared
/// [EveningPlanService] so getting a ticket on one screen is reflected
/// on the other two right away.
///
/// Several evenings can be planned at once (see [EveningPlanService]),
/// but this card only ever shows one ticket: whichever is soonest. If
/// others are queued up behind it, a small "+N more" tab on the stub
/// opens [_AllPlansSheet] to see and manage the rest — the card itself
/// stays a single, uncluttered ticket either way.
///
/// Two very different looks share this one widget on purpose: an empty,
/// inviting CTA when nothing's planned, and a poster-topped ticket once
/// something is — same "the state IS the screen" idea as [TicketWidget]
/// itself, just one level up. [coViewingByDefault] only affects the sheet
/// this opens (see [showPlanEveningSheet]'s own docstring).
class EveningPlanCard extends StatelessWidget {
  final bool coViewingByDefault;

  const EveningPlanCard({super.key, this.coViewingByDefault = false});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EveningPlanService>();
    if (!service.loaded) return const SizedBox.shrink();
    final plan = service.plan;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
        ),
      ),
      child: plan == null
          ? _EmptyEveningCard(
              key: const ValueKey('empty'),
              coViewingByDefault: coViewingByDefault,
            )
          : _PlannedEveningCard(
              key: ValueKey(plan.id),
              plan: plan,
              otherCount: service.otherPlansCount,
              coViewingByDefault: coViewingByDefault,
            ),
    );
  }
}

/// Nothing planned yet — a soft, low-pressure invitation rather than an
/// empty state that reads as a chore. Same paper card language as the
/// rest of the app, dressed in a dashed edge (see [DashedBox]'s own
/// reasoning) so it reads as "a slot waiting to be filled" rather than
/// a fully-formed card with nothing in it.
class _EmptyEveningCard extends StatelessWidget {
  final bool coViewingByDefault;
  const _EmptyEveningCard({super.key, required this.coViewingByDefault});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showPlanEveningSheet(context, coViewingByDefault: coViewingByDefault),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: SeenlyPalette.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.local_activity_outlined, size: 21, color: SeenlyPalette.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('plan an evening', style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    'pick a title, pick a date, get a ticket',
                    style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Something's planned — the poster on top, a torn-paper seam, then a
/// ticket-stub footer with the date and (if it's a co-viewing evening) who
/// with. The reminder line lives right in the stub rather than as a
/// separate banner, so there's exactly one place on the screen that's
/// ever telling you about tonight.
class _PlannedEveningCard extends StatefulWidget {
  final PlannedEvening plan;
  final int otherCount;
  final bool coViewingByDefault;
  const _PlannedEveningCard({
    super.key,
    required this.plan,
    this.otherCount = 0,
    this.coViewingByDefault = false,
  });

  @override
  State<_PlannedEveningCard> createState() => _PlannedEveningCardState();
}

class _PlannedEveningCardState extends State<_PlannedEveningCard> {
  bool _busy = false;

  void _openTitle() {
    final plan = widget.plan;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TitleDetailScreen(
          mediaId: plan.mediaId,
          source: plan.source,
          mediaType: plan.mediaType,
          seedTitle: plan.title,
          seedPosterUrl: plan.posterUrl,
        ),
      ),
    );
  }

  Future<void> _markWatched() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().feed.react(widget.plan.toMediaItem(), 'watched');
      await context.read<EveningPlanService>().clear(widget.plan.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't mark that watched — try again")),
      );
    }
  }

  Future<void> _clearPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('let this plan go?', style: SeenlyText.serif(size: 15)),
        content: Text(
          '"${widget.plan.title}" comes off your ticket — you can always plan another evening.',
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('keep it', style: SeenlyText.mono(size: 11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('let it go', style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<EveningPlanService>().clear(widget.plan.id);
    }
  }

  void _planAnother() {
    showPlanEveningSheet(context, coViewingByDefault: widget.coViewingByDefault);
  }

  void _showAllPlans() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _AllPlansSheet(),
    );
  }

  String get _reminderText {
    final plan = widget.plan;
    if (plan.isPast) return 'was this evening — did you watch it?';
    if (plan.isToday) return 'tonight\'s the night';
    if (plan.isTomorrow) return 'coming up tomorrow';
    if (plan.daysUntil <= 7) return 'in ${plan.daysUntil} days';
    return _formatDate(plan.date);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final accent = plan.isPast ? SeenlyPalette.inkFaint : SeenlyPalette.accent;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poster, with a little "reminder ribbon" riding its top-right
          // corner — the countdown lives here rather than as a separate
          // banner elsewhere on the page, so this card is the one place
          // that ever mentions the evening.
          GestureDetector(
            onTap: _openTitle,
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: plan.posterUrl != null && plan.posterUrl!.isNotEmpty
                      ? Image.network(
                          plan.posterUrl!,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.55),
                          errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(plan.mediaType)),
                        )
                      : Container(
                          color: SeenlyPalette.mediaColor(plan.mediaType),
                          alignment: Alignment.center,
                          child: const Icon(Icons.movie_creation_outlined, color: SeenlyPalette.paper, size: 30),
                        ),
                ),
                // Soft gradient so the ribbon and (if present) the
                // co-viewing chip always sit readably over the art
                // underneath, whatever the poster's own colors are.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SeenlyPalette.ink.withOpacity(0.28),
                          Colors.transparent,
                          SeenlyPalette.ink.withOpacity(0.05),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: SeenlyPalette.softShadow,
                    ),
                    child: Text(
                      _reminderText,
                      style: SeenlyText.mono(
                        size: 10,
                        color: SeenlyPalette.accentOnAccent,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (plan.coViewing)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.paper.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite, size: 10, color: SeenlyPalette.accent),
                          const SizedBox(width: 4),
                          Text(
                            plan.partnerUsername ?? 'together',
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.ink, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(
                      italic: true,
                      size: 15,
                      weight: FontWeight.w600,
                      color: SeenlyPalette.paper,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The torn-paper seam between poster and stub — same jagged
          // language as TearTicketConfirm's own seam, just static here:
          // this ticket has already been torn free once (see the sheet's
          // confirm step), this is just what it looks like at rest.
          CustomPaint(
            painter: _SeamPainter(color: SeenlyPalette.background),
            size: const Size(double.infinity, 10),
          ),
          Container(
            color: SeenlyPalette.background,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        [
                          plan.isPast
                              ? 'mark it watched, or let this plan go'
                              : plan.coViewing
                                  ? 'a co-viewing evening'
                                  : 'your evening, on the calendar',
                          if (plan.hasTime) plan.timeLabel!,
                        ].join(' · '),
                        style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted),
                      ),
                      // Other evenings queued up behind this one, if any
                      // — this ticket only ever shows the soonest, so
                      // this is the one hint that there's more waiting.
                      if (widget.otherCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: GestureDetector(
                            onTap: _showAllPlans,
                            child: Text(
                              '+${widget.otherCount} more planned',
                              style: SeenlyText.mono(
                                size: 10,
                                color: SeenlyPalette.accent,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _planAnother,
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, size: 15, color: SeenlyPalette.accent),
                  ),
                ),
                if (plan.isPast) ...[
                  GestureDetector(
                    onTap: _busy ? null : _markWatched,
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(6),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('watched',
                                style: SeenlyText.mono(
                                    size: 10, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w600)),
                          ),
                  ),
                  const SizedBox(width: 6),
                ],
                GestureDetector(
                  onTap: _clearPlan,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 13, color: SeenlyPalette.inkFaint),
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

/// Everything planned, not just the soonest — opened from the "+N more
/// planned" tab on the main ticket. A plain list rather than a stack of
/// mini-tickets: this is the "manage all of them" view, so legibility
/// and quick actions matter more than the ceremony the main card gets.
class _AllPlansSheet extends StatelessWidget {
  const _AllPlansSheet();

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<EveningPlanService>().plans;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SeenlyPalette.dashedBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('your planned evenings', style: SeenlyText.serif(italic: true, size: 16)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      showPlanEveningSheet(context);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.add, size: 15, color: SeenlyPalette.accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: plans.isEmpty
                  ? Center(
                      child: Text(
                        'nothing planned right now',
                        style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: plans.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _AllPlansRow(plan: plans[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllPlansRow extends StatefulWidget {
  final PlannedEvening plan;
  const _AllPlansRow({required this.plan});

  @override
  State<_AllPlansRow> createState() => _AllPlansRowState();
}

class _AllPlansRowState extends State<_AllPlansRow> {
  bool _busy = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _label {
    final plan = widget.plan;
    final day = plan.isPast
        ? 'was this evening'
        : plan.isToday
            ? 'tonight'
            : plan.isTomorrow
                ? 'tomorrow'
                : '${_months[plan.date.month - 1]} ${plan.date.day}';
    return plan.hasTime ? '$day · ${plan.timeLabel}' : day;
  }

  Future<void> _markWatched() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().feed.react(widget.plan.toMediaItem(), 'watched');
      await context.read<EveningPlanService>().clear(widget.plan.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("couldn't mark that watched — try again")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TitleDetailScreen(
              mediaId: plan.mediaId,
              source: plan.source,
              mediaType: plan.mediaType,
              seedTitle: plan.title,
              seedPosterUrl: plan.posterUrl,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 36,
                height: 52,
                child: plan.posterUrl != null && plan.posterUrl!.isNotEmpty
                    ? Image.network(
                        plan.posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.mediaColor(plan.mediaType)),
                      )
                    : Container(color: SeenlyPalette.mediaColor(plan.mediaType)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plan.coViewing ? '$_label · with ${plan.partnerUsername ?? 'partner'}' : _label,
                    style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                  ),
                ],
              ),
            ),
            if (plan.isPast)
              GestureDetector(
                onTap: _busy ? null : _markWatched,
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text('watched',
                            style: SeenlyText.mono(
                                size: 9.5, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w600)),
                      ),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => context.read<EveningPlanService>().clear(plan.id),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.close, size: 12, color: SeenlyPalette.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft, irregular tear line — same reasoning as [TearTicketConfirm]'s
/// `_raggedSeam`, just painted flat instead of split into two halves.
class _SeamPainter extends CustomPainter {
  final Color color;
  const _SeamPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const teeth = 22;
    const amplitude = 3.0;
    final rnd = _seededRandom(9173);
    final stepW = size.width / teeth;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i <= teeth; i++) {
      final dy = i == 0 || i == teeth ? size.height * 0.5 : size.height * 0.5 + (rnd(i) * 2 - 1) * amplitude;
      path.lineTo(i * stepW, dy);
    }
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // A tiny deterministic pseudo-random helper (no dart:math Random kept
  // around as state) — same tooth pattern every rebuild so the seam
  // doesn't visibly jitter each time this repaints.
  double Function(int) _seededRandom(int seed) {
    return (int i) {
      final x = (seed * 9301 + i * 49297) % 233280;
      return x / 233280;
    };
  }

  @override
  bool shouldRepaint(covariant _SeamPainter oldDelegate) => oldDelegate.color != color;
}
