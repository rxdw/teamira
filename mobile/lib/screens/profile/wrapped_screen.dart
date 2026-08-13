import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/profile_stats.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_loading_indicator.dart';

/// Profile -> Wrapped: the full "envelope -> cards -> letter -> receipt"
/// recap flow, for whichever period the person picks — this month, this
/// year, any earlier month/year they've actually logged something in, or
/// their whole history. Every number on every card comes straight off one
/// WrappedSummary fetch (see ProfileService.wrappedSummary) — nothing
/// here is computed client-side, and every label uses the app's own
/// fonts (see theme/text_styles.dart) rather than anything bespoke.
class WrappedScreen extends StatefulWidget {
  final String initialScope; // "month" | "year" | "all"
  final int? initialYear;
  final int? initialMonth;
  const WrappedScreen({
    super.key,
    this.initialScope = 'year',
    this.initialYear,
    this.initialMonth,
  });

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  late Future<WrappedSummary> _future;
  late String _scope;
  int? _year;
  int? _month;
  bool _opened = false;
  Future<WrappedPeriods>? _periodsFuture;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _year = widget.initialYear;
    _month = widget.initialMonth;
    _future = _load();
  }

  Future<WrappedSummary> _load() =>
      context.read<AppState>().profile.wrappedSummary(scope: _scope, year: _year, month: _month);

  void _switchTo(String scope, {int? year, int? month}) {
    setState(() {
      _scope = scope;
      _year = year;
      _month = month;
      _future = _load();
    });
  }

  Future<void> _openPicker(WrappedSummary current) async {
    _periodsFuture ??= context.read<AppState>().profile.wrappedPeriods();
    final periods = await _periodsFuture!;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PeriodPickerSheet(
        periods: periods,
        currentScope: _scope,
        currentYear: _year,
        currentMonth: _month,
        onSelect: (scope, year, month) {
          Navigator.of(context).pop();
          _switchTo(scope, year: year, month: month);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      // The carousel manages its own SafeArea internally so its poster
      // background can run truly edge-to-edge (behind the status bar and
      // home indicator too) — every other state here still gets the plain
      // outer SafeArea since it has no full-bleed art to protect.
      body: FutureBuilder<WrappedSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const SafeArea(child: Center(child: ThemedLoadingIndicator()));
          }
          if (snapshot.hasError) {
            return SafeArea(
              child: _MessageScreen(
                text: "не получилось загрузить эту сводку",
                onClose: () => Navigator.of(context).pop(),
              ),
            );
          }
          final summary = snapshot.data!;
          if (summary.totalLogged == 0) {
            return SafeArea(
              child: _MessageScreen(
                text: "за ${summary.periodLabel} в дневнике пока пусто —\nвозвращайся, когда появятся записи",
                onClose: () => Navigator.of(context).pop(),
                onPickPeriod: () => _openPicker(summary),
              ),
            );
          }
          if (!_opened) {
            return SafeArea(
              child: _EnvelopeScreen(
                onOpen: () => setState(() => _opened = true),
                onClose: () => Navigator.of(context).pop(),
              ),
            );
          }
          return _WrappedCarousel(
            summary: summary,
            onPickPeriod: () => _openPicker(summary),
          );
        },
      ),
    );
  }
}

/// Bottom sheet listing every period the account actually has entries in
/// — "этот месяц"/"этот год"/"за всё время" up top, then every earlier
/// month and year with real data underneath. Never offers an empty period.
class _PeriodPickerSheet extends StatelessWidget {
  final WrappedPeriods periods;
  final String currentScope;
  final int? currentYear;
  final int? currentMonth;
  final void Function(String scope, int? year, int? month) onSelect;

  const _PeriodPickerSheet({
    required this.periods,
    required this.currentScope,
    required this.currentYear,
    required this.currentMonth,
    required this.onSelect,
  });

  static const _monthNames = [
    '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = currentScope == 'month' && (currentYear ?? now.year) == now.year &&
        (currentMonth ?? now.month) == now.month;
    final isCurrentYear = currentScope == 'year' && (currentYear ?? now.year) == now.year;
    final isAll = currentScope == 'all';

    final otherMonths = periods.months
        .where((p) => !(p.year == now.year && p.month == now.month))
        .toList();
    final otherYears = periods.years.where((y) => y != now.year).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: SeenlyPalette.dashedBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('выбрать период', style: SeenlyText.sectionTitle),
            const SizedBox(height: 12),
            _PeriodTile(
              label: 'этот месяц',
              active: isCurrentMonth,
              onTap: () => onSelect('month', now.year, now.month),
            ),
            _PeriodTile(
              label: 'этот год',
              active: isCurrentYear,
              onTap: () => onSelect('year', now.year, null),
            ),
            _PeriodTile(
              label: 'за всё время',
              active: isAll,
              onTap: () => onSelect('all', null, null),
            ),
            if (otherYears.isNotEmpty || otherMonths.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(color: SeenlyPalette.dashedBorder, height: 1),
              const SizedBox(height: 10),
            ],
            if (otherYears.isNotEmpty) ...[
              Text('годы', style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder)),
              const SizedBox(height: 4),
              for (final y in otherYears)
                _PeriodTile(
                  label: '$y',
                  active: currentScope == 'year' && currentYear == y,
                  onTap: () => onSelect('year', y, null),
                ),
            ],
            if (otherMonths.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('месяцы', style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder)),
              const SizedBox(height: 4),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: otherMonths.length,
                  itemBuilder: (context, i) {
                    final p = otherMonths[i];
                    return _PeriodTile(
                      label: '${_monthNames[p.month]} ${p.year}',
                      active: currentScope == 'month' && currentYear == p.year && currentMonth == p.month,
                      onTap: () => onSelect('month', p.year, p.month),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PeriodTile({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: SeenlyText.serif(size: 14, color: active ? SeenlyPalette.accent : SeenlyPalette.ink,
                      weight: active ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (active) const Icon(Icons.check, size: 16, color: SeenlyPalette.accent),
          ],
        ),
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  final VoidCallback? onPickPeriod;
  const _MessageScreen({required this.text, required this.onClose, this.onPickPeriod});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.close, size: 18, color: SeenlyPalette.ink),
            onPressed: onClose,
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(color: SeenlyPalette.inkMuted),
                  ),
                  if (onPickPeriod != null) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: onPickPeriod,
                      child: Text('выбрать другой период',
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent, weight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

class _EnvelopeScreen extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onClose;
  const _EnvelopeScreen({required this.onOpen, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.close, size: 18, color: SeenlyPalette.ink),
            onPressed: onClose,
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CustomPaint(painter: _EnvelopePainter()),
                  ),
                  const SizedBox(height: 28),
                  Text('запечатано · тапни, чтобы открыть',
                      style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bodyTop = h * 0.32;
    final flapPaint = Paint()..color = SeenlyPalette.cork;
    final bodyPaint = Paint()..color = SeenlyPalette.paper;

    final flapPath = Path()
      ..moveTo(w * 0.06, bodyTop)
      ..lineTo(w * 0.5, h * 0.02)
      ..lineTo(w * 0.94, bodyTop)
      ..close();
    canvas.drawPath(flapPath, flapPaint);

    final bodyRect = Rect.fromLTWH(w * 0.06, bodyTop, w * 0.88, h * 0.62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(10)),
      bodyPaint,
    );

    final sealPaint = Paint()..color = SeenlyPalette.accent;
    final sealCenter = Offset(w * 0.5, bodyTop + h * 0.22);
    canvas.drawCircle(sealCenter, w * 0.13, sealPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'T',
        style: TextStyle(
          color: SeenlyPalette.accentOnAccent,
          fontSize: w * 0.14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      sealCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Carousel shell
// ---------------------------------------------------------------------------

class _WrappedCarousel extends StatefulWidget {
  final WrappedSummary summary;
  final VoidCallback onPickPeriod;
  const _WrappedCarousel({required this.summary, required this.onPickPeriod});

  @override
  State<_WrappedCarousel> createState() => _WrappedCarouselState();
}

class _WrappedCarouselState extends State<_WrappedCarousel> {
  late final PageController _controller;
  int _page = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    final s = widget.summary;
    _pages = [
      _OverviewSessionsCard(summary: s, onNext: _next),
      _ClockCard(summary: s, onNext: _next),
      _GenreStripCard(summary: s, onNext: _next),
      _FirstLastCard(summary: s, onNext: _next),
      _DirectorsCard(summary: s, onNext: _next),
      _DecadeCard(summary: s, onNext: _next),
      _NewVsRewatchCard(summary: s, onNext: _next),
      _TimelineCard(summary: s, onNext: _next),
      _WeekdayCard(summary: s, onNext: _next),
      _SoloCompanyCard(summary: s, onNext: _next),
      _ArchetypeCard(summary: s, onNext: _next),
      _ReviewsOverviewCard(summary: s, onNext: _next),
      if (s.favoriteReview != null) _FavoriteReviewCard(summary: s, onNext: _next),
      _LetterCard(summary: s, onNext: _next),
      _ReceiptCard(summary: s),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _pages.length - 1) return;
    _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  void _prev() {
    if (_page <= 0) return;
    _controller.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Sits outside the SafeArea below so it actually reaches the
        // physical screen edges — behind the status bar and the home
        // indicator — instead of stopping at the safe-area inset with a
        // hard, cheap-looking cut. Same night-sky ingredients as
        // onboarding (see screens/onboarding/onboarding_screen.dart) so
        // the two "occasion" flows in the app share one visual language,
        // rather than Wrapped inventing its own.
        const Positioned.fill(child: _WrappedNightBackdrop()),
        // The chapter's own progress, drawn as a constellation instead of
        // little dots — one star per screen in this chapter, lighting up
        // and connecting to the last as you move forward.
        Positioned.fill(child: _ConstellationBackdrop(page: _page, pageCount: _pages.length)),
        // A soft one-shot bloom for the whole deck the moment Wrapped
        // opens — the sky and the constellation are already there
        // instantly, but the cards themselves rise and fade in gently
        // rather than snapping onto the screen. Only plays once: since
        // begin/end/duration below never change, TweenAnimationBuilder
        // settles at the target and stays there through every later
        // rebuild (page swipes, period changes, etc.).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 640),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
          ),
          child: SafeArea(child: _WrappedCarouselContent(
            page: _page,
            pages: _pages,
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            onNext: _next,
            onPrev: _prev,
            periodLabel: widget.summary.periodLabel,
            onPickPeriod: widget.onPickPeriod,
            onClose: () => Navigator.of(context).pop(),
          )),
        ),
      ],
    );
  }
}

/// Foreground chrome (close/period header, dots, cards, chevrons) for the
/// carousel — split out from [_WrappedCarouselState] so the full-bleed
/// poster behind it can sit in its own Stack layer, unclipped by SafeArea.
class _WrappedCarouselContent extends StatelessWidget {
  final int page;
  final List<Widget> pages;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final String periodLabel;
  final VoidCallback onPickPeriod;
  final VoidCallback onClose;

  const _WrappedCarouselContent({
    required this.page,
    required this.pages,
    required this.controller,
    required this.onPageChanged,
    required this.onNext,
    required this.onPrev,
    required this.periodLabel,
    required this.onPickPeriod,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              Container(
                decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: SeenlyPalette.ink),
                  onPressed: onClose,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPickPeriod,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(periodLabel,
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink, weight: FontWeight.w600)),
                      const SizedBox(width: 3),
                      const Icon(Icons.expand_more, size: 13, color: SeenlyPalette.inkFaint),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // The little dot row used to be the only progress indicator;
              // now the constellation behind the whole screen (see
              // _ConstellationBackdrop, painted across the top of the sky)
              // does that job instead, so this header goes back to just
              // close + period — the sky itself carries "how far along".
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: pages.length,
                itemBuilder: (context, i) => Padding(
                  // Cards are full width but no longer forced to full
                  // device height (see _CardShell) — short-content
                  // screens (a single poster + a line of text) were
                  // getting stretched to fill the whole viewport and
                  // just floating, tiny, in a sea of dead color.
                  // Centering a content-sized card here means every
                  // screen is exactly as tall as what it's showing.
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: Center(child: _CardSwipeMotion(controller: controller, index: i, fallbackPage: page, child: pages[i])),
                ),
              ),
              if (page > 0)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavChevron(icon: Icons.chevron_left, onTap: onPrev),
                  ),
                ),
              if (page < pages.length - 1)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavChevron(icon: Icons.chevron_right, onTap: onNext),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavChevron extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavChevron({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: SeenlyPalette.inkMuted),
      ),
    );
  }
}

/// Wraps one card so it responds to the live scroll position rather than
/// only snapping between two fixed states — as the person drags between
/// screens, the outgoing card softly sinks, fades, and shrinks a touch
/// while the incoming one rises and grows into place, all in the same
/// motion as the finger. This one widget is what makes every screen in
/// the deck animate, rather than hand-animating each of the fourteen
/// cards separately.
class _CardSwipeMotion extends StatelessWidget {
  final PageController controller;
  final int index;
  final int fallbackPage;
  final Widget child;
  const _CardSwipeMotion({
    required this.controller,
    required this.index,
    required this.fallbackPage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        double page = fallbackPage.toDouble();
        // controller.page throws if no PageView is attached yet (the very
        // first frame) — falls back to the known current index then.
        if (controller.hasClients) {
          try {
            page = controller.page ?? fallbackPage.toDouble();
          } catch (_) {}
        }
        final delta = (page - index).clamp(-1.0, 1.0);
        final settle = delta.abs();
        return Opacity(
          opacity: 1 - settle * 0.55,
          child: Transform.translate(
            offset: Offset(0, settle * 22),
            child: Transform.scale(
              scale: 1 - settle * 0.08,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A number that softly counts up to [value] the first time it appears —
/// used for the deck's headline stats rather than having them just pop
/// into place fully-formed.
class _CountUp extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String Function(int)? format;
  final Duration duration;
  const _CountUp({required this.value, required this.style, this.format, this.duration = const Duration(milliseconds: 900)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final n = v.round();
        return Text(format != null ? format!(n) : '$n', style: style);
      },
    );
  }
}

/// Fades and gently rises into place after a per-item delay — used to
/// stagger a list or a row of chips in one after another instead of
/// having them all pop in at once.
class _StaggerFade extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration gap;
  const _StaggerFade({required this.index, required this.child, this.gap = const Duration(milliseconds: 70)});

  @override
  State<_StaggerFade> createState() => _StaggerFadeState();
}

class _StaggerFadeState extends State<_StaggerFade> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.gap * widget.index, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.12),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A bar that grows from zero to [height] on entrance, its start staggered
/// by [delay] (0..1, the bar's position within the row) so a chart fills
/// in left-to-right rather than every bar snapping up at once.
class _GrowBar extends StatelessWidget {
  final double height;
  final Color color;
  final double delay;
  final BorderRadius borderRadius;
  const _GrowBar({required this.height, required this.color, required this.delay, this.borderRadius = const BorderRadius.vertical(top: Radius.circular(3))});

  @override
  Widget build(BuildContext context) {
    final start = delay.clamp(0.0, 0.55);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: height),
      duration: const Duration(milliseconds: 800),
      curve: Interval(start, (start + 0.45).clamp(0.45, 1.0), curve: Curves.easeOutCubic),
      builder: (context, h, _) => Container(
        height: h,
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card shell
// ---------------------------------------------------------------------------

class _CardShell extends StatelessWidget {
  final String bonusLabel;
  final Widget child;
  final VoidCallback? onNext;
  final bool compact;
  final Widget? shareButton;
  // Full-bleed background for this one screen, pulled straight from the
  // app's existing categorical palette (palette.dart) — never a new hex.
  // Wrapped is a once-a-year, festive recap rather than an everyday
  // screen, so unlike the rest of the app (deliberately a muted paper
  // diary — see the note at the top of palette.dart) each chapter here
  // gets its own full color identity, the way the reference decks did.
  final Color background;
  // Whether `background` reads dark enough that content needs the paper
  // foreground instead of ink. Set per card below by eye, not computed
  // from luminance — mustard and the receipt's own paper both count as
  // "light" even though they're not literally white.
  final bool light;

  const _CardShell({
    required this.bonusLabel,
    required this.child,
    this.onNext,
    this.compact = false,
    this.shareButton,
    this.background = SeenlyPalette.accent,
    this.light = true,
  });

  Color get _fg => light ? SeenlyPalette.paper : SeenlyPalette.ink;
  Color get _chipBg => light ? Colors.white.withOpacity(0.16) : SeenlyPalette.ink.withOpacity(0.10);

  @override
  Widget build(BuildContext context) {
    // A cinema ticket, not a floating paper card: two punched notches at
    // mid-height, built with the same rect-minus-two-circles path
    // BoardingPassWidget already uses elsewhere in the app (see
    // widgets/boarding_pass.dart) — reused here as a ShapeBorder so the
    // card's own drop shadow still follows the notched outline correctly,
    // rather than being clipped away by a separate ClipPath on top.
    //
    // Sized to its own content (with a floor, not forced to fill the full
    // device height): a card stretched to the whole viewport just leaves
    // short-content screens — a poster and a line of text — stranded as a
    // tiny cluster in a huge dead field of color. Centered by the caller
    // (_WrappedCarouselContent) instead, the way a real printed ticket
    // sits on a page rather than being blown up to the page's own size.
    return _CardTone(
      fg: _fg,
      chipBg: _chipBg,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 4, vertical: 8),
        child: LayoutBuilder(builder: (context, outer) {
          final floor = math.min(440.0, outer.maxHeight);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: outer.maxHeight),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: floor),
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: background,
                    shape: const _TicketNotchBorder(),
                    shadows: SeenlyPalette.softShadow,
                  ),
                  padding: EdgeInsets.fromLTRB(24, compact ? 18 : 22, 24, compact ? 18 : 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(color: _chipBg, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            bonusLabel.toUpperCase(),
                            style: SeenlyText.mono(size: 11, color: _fg, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      child,
                      if (shareButton != null) ...[
                        const SizedBox(height: 16),
                        shareButton!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Cuts two circular notches out of a rounded rect at mid-height, left and
/// right — the exact same "ticket" construction as `_MainBodyClipper` /
/// `_StubClipper` in widgets/boarding_pass.dart, expressed as a ShapeBorder
/// instead of a CustomClipper so a plain Container's own `shadows` still
/// render correctly around the notched outline.
class _TicketNotchBorder extends ShapeBorder {
  final double radius;
  final double notchRadius;
  const _TicketNotchBorder({this.radius = 26, this.notchRadius = 10});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final base = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(rect.left, rect.center.dy), radius: notchRadius))
      ..addOval(Rect.fromCircle(center: Offset(rect.right, rect.center.dy), radius: notchRadius));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// Makes a card's foreground colors available to its content via
/// InheritedWidget, so each card body can just ask `_CardTone.of(context)`
/// instead of every single card re-deriving "am I light or dark" itself.
class _CardTone extends InheritedWidget {
  final Color fg;
  final Color chipBg;
  const _CardTone({required this.fg, required this.chipBg, required super.child});

  static _CardTone of(BuildContext context) {
    final found = context.dependOnInheritedWidgetOfExactType<_CardTone>();
    // Falls back to ink-on-paper for anything built outside a _CardShell —
    // the receipt card paints its own paper container directly rather
    // than going through _CardShell, so shared tone-aware widgets like
    // _ShareButton still need a sane default there.
    return found ?? const _CardTone(fg: SeenlyPalette.ink, chipBg: SeenlyPalette.cork, child: SizedBox.shrink());
  }

  Color get fgMuted => fg.withOpacity(0.72);
  Color get fgFaint => fg.withOpacity(0.5);

  @override
  bool updateShouldNotify(_CardTone oldWidget) => oldWidget.fg != fg || oldWidget.chipBg != chipBg;
}

/// A short horizontal dashed rule — the "tear line" on a ticket — used
/// between a card's headline content and its footnote. Stretches to fill
/// whatever width it's given.
class _TicketDash extends StatelessWidget {
  final Color? color;
  const _TicketDash({this.color});
  @override
  Widget build(BuildContext context) {
    final resolved = color ?? _CardTone.of(context).fg.withOpacity(0.28);
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: CustomPaint(painter: _DashPainter(resolved)),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    const dash = 5.0, gap = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + dash, size.height / 2), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.color != color;
}

/// Plain warm backdrop behind the whole wrapped screen. Each card is now a
/// full-bleed color ticket in its own right (see [_CardShell]), so a
/// blurred movie poster peeking through here would just fight the card's
/// own color rather than frame it — simple paper instead, the same tone
/// the rest of the app rests on. It still lives outside the SafeArea below
/// so it reaches the true screen edges rather than stopping at the inset.
// ---------------------------------------------------------------------------
// Night sky — reused wholesale from the onboarding flow (see
// screens/onboarding/onboarding_screen.dart: _AuroraBackdrop,
// _StarfieldBackdrop, _ShootingStarBackdrop, _ConstellationBackdrop and
// their painters) rather than reinvented, so this is the same "occasion"
// visual language the app already established there — Wrapped is the
// other once-in-a-while moment in the app, not an everyday screen.
// ---------------------------------------------------------------------------

/// Same night color as onboarding (`_OnboardingScreenState._nightColor`),
/// duplicated here rather than imported since that constant is private to
/// the onboarding file.
const _wrappedNightColor = Color(0xFF241A22);

class _WrappedNightBackdrop extends StatelessWidget {
  const _WrappedNightBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: _wrappedNightColor),
        _AuroraBackdrop(),
        _StarfieldBackdrop(),
        _ShootingStarBackdrop(),
      ],
    );
  }
}

/// Four soft, blurred blobs of colour anchored near the corners, drifting
/// gently and cross-fading between palette hues over roughly 20 seconds —
/// see the onboarding original for the full rationale.
class _AuroraBackdrop extends StatefulWidget {
  const _AuroraBackdrop();

  @override
  State<_AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<_AuroraBackdrop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();

  static const _blobColors = [
    SeenlyPalette.coral,
    SeenlyPalette.periwinkle,
    SeenlyPalette.mustard,
    SeenlyPalette.pink,
    SeenlyPalette.sage,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AuroraPainter(t: _controller.value, colors: _blobColors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  const _AuroraPainter({required this.t, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final anchors = [
      Offset(size.width * 0.16, size.height * 0.14),
      Offset(size.width * 0.88, size.height * 0.20),
      Offset(size.width * 0.22, size.height * 0.84),
      Offset(size.width * 0.84, size.height * 0.88),
    ];
    for (int i = 0; i < anchors.length; i++) {
      final phase = (t + i / anchors.length) % 1.0;
      final colorA = colors[i % colors.length];
      final colorB = colors[(i + 1) % colors.length];
      final mix = math.sin(phase * 2 * math.pi) * 0.5 + 0.5;
      final color = Color.lerp(colorA, colorB, mix)!;
      final drift = Offset(
        math.sin((t + i) * 2 * math.pi) * 20,
        math.cos((t + i * 1.3) * 2 * math.pi) * 16,
      );
      final paint = Paint()
        ..color = color.withOpacity(0.17)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
      canvas.drawCircle(anchors[i] + drift, size.shortestSide * 0.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => oldDelegate.t != t;
}

/// A single comet that streaks across the sky at random, irregular
/// intervals — see the onboarding original for the full rationale.
class _ShootingStarBackdrop extends StatefulWidget {
  const _ShootingStarBackdrop();

  @override
  State<_ShootingStarBackdrop> createState() => _ShootingStarBackdropState();
}

class _ShootingStarBackdropState extends State<_ShootingStarBackdrop> with SingleTickerProviderStateMixin {
  static const _flightDuration = Duration(milliseconds: 850);
  final _rnd = math.Random();

  late final AnimationController _controller = AnimationController(vsync: this, duration: _flightDuration);
  Timer? _scheduleTimer;

  Offset _start = Offset.zero;
  Offset _end = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    final wait = Duration(milliseconds: 6000 + _rnd.nextInt(5000));
    _scheduleTimer = Timer(wait, _fly);
  }

  void _fly() {
    if (!mounted) return;
    final fromLeft = _rnd.nextBool();
    setState(() {
      _start = Offset(fromLeft ? -0.08 : 1.08, 0.02 + _rnd.nextDouble() * 0.22);
      _end = Offset(fromLeft ? 0.55 + _rnd.nextDouble() * 0.35 : 0.10 - _rnd.nextDouble() * 0.35,
          0.42 + _rnd.nextDouble() * 0.3);
    });
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) _scheduleNext();
    });
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ShootingStarPainter(t: _controller.value, start: _start, end: _end),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ShootingStarPainter extends CustomPainter {
  final double t;
  final Offset start;
  final Offset end;
  const _ShootingStarPainter({required this.t, required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final eased = Curves.easeOutCubic.transform(t);
    final head = Offset(
      (start.dx + (end.dx - start.dx) * eased) * size.width,
      (start.dy + (end.dy - start.dy) * eased) * size.height,
    );
    final tailEased = Curves.easeOutCubic.transform((t - 0.16).clamp(0.0, 1.0));
    final tail = Offset(
      (start.dx + (end.dx - start.dx) * tailEased) * size.width,
      (start.dy + (end.dy - start.dy) * tailEased) * size.height,
    );
    final opacity = t < 0.10 ? t / 0.10 : (t > 0.75 ? (1 - t) / 0.25 : 1.0);
    if (opacity <= 0) return;

    final trailPaint = Paint()
      ..shader = ui.Gradient.linear(tail, head, [
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(0.85 * opacity.clamp(0.0, 1.0)),
      ])
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, head, trailPaint);

    final headPaint = Paint()..color = Colors.white.withOpacity(opacity.clamp(0.0, 1.0));
    canvas.drawCircle(head, 1.8, headPaint);
    final glowPaint = Paint()
      ..color = SeenlyPalette.mustard.withOpacity(0.35 * opacity.clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(head, 4, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.start != start || oldDelegate.end != end;
}

/// The chapter's progress, drawn as a constellation instead of a progress
/// bar — [page]/[pageCount] here are the current screen's index within
/// the whole Wrapped deck (all 14 cards), not just one chapter, so by the
/// last screen the whole sky is lit. See the onboarding original for the
/// full rationale.
class _ConstellationBackdrop extends StatefulWidget {
  final int page;
  final int pageCount;
  const _ConstellationBackdrop({required this.page, required this.pageCount});

  @override
  State<_ConstellationBackdrop> createState() => _ConstellationBackdropState();
}

class _ConstellationBackdropState extends State<_ConstellationBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.page.toDouble(), end: widget.page.toDouble()),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return AnimatedBuilder(
          animation: _twinkle,
          builder: (context, __) => CustomPaint(
            painter: _ConstellationPainter(
              progress: progress,
              twinkle: _twinkle.value,
              nodeCount: widget.pageCount,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  final double progress;
  final double twinkle;
  final int nodeCount;
  const _ConstellationPainter({required this.progress, required this.twinkle, required this.nodeCount});

  // Fractional (0..1, 0..1) positions, hand-placed in a loose arc rather
  // than evenly spaced — reused as-is from onboarding. With up to 14
  // Wrapped screens (more than onboarding's 8 fixed points), extra nodes
  // beyond this list fall back to an evenly-spaced row further down —
  // see [_extraNodesFrac].
  static const _nodesFrac = [
    Offset(0.10, 0.10),
    Offset(0.20, 0.05),
    Offset(0.31, 0.09),
    Offset(0.42, 0.04),
    Offset(0.53, 0.08),
    Offset(0.64, 0.04),
    Offset(0.75, 0.08),
    Offset(0.86, 0.05),
    Offset(0.93, 0.11),
  ];

  List<Offset> _resolveNodes(Size size) {
    if (nodeCount <= _nodesFrac.length) {
      return [for (int i = 0; i < nodeCount; i++) Offset(_nodesFrac[i].dx * size.width, _nodesFrac[i].dy * size.height)];
    }
    // More screens than hand-placed points (Wrapped can run to 14 cards):
    // spread the rest evenly along a slightly lower second arc rather
    // than crowding them into the same nine spots.
    final nodes = [for (final f in _nodesFrac) Offset(f.dx * size.width, f.dy * size.height)];
    final extra = nodeCount - _nodesFrac.length;
    for (int i = 0; i < extra; i++) {
      final dx = 0.08 + (i / math.max(1, extra - 1)) * 0.84;
      final dy = 0.17 + (i.isEven ? 0.0 : 0.04);
      nodes.add(Offset(dx * size.width, dy * size.height));
    }
    return nodes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = _resolveNodes(size);
    final pulse = 0.72 + 0.28 * twinkle;

    final glowLine = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final crispLine = Paint()
      ..color = SeenlyPalette.paper.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < nodes.length - 1; i++) {
      final segT = (progress - i).clamp(0.0, 1.0);
      if (segT <= 0) continue;
      final a = nodes[i];
      final b = Offset.lerp(nodes[i], nodes[i + 1], segT)!;
      canvas.drawLine(a, b, glowLine);
      canvas.drawLine(a, b, crispLine);
    }

    for (int i = 0; i < nodes.length; i++) {
      final reached = progress >= i - 0.001;
      if (!reached) {
        final dim = Paint()..color = Colors.white.withOpacity(0.14);
        canvas.drawCircle(nodes[i], 1.6, dim);
        continue;
      }
      final isCurrent = (progress - i).abs() < 0.5;
      final glowR = isCurrent ? 11.0 * pulse : 5.0;
      final glow = Paint()
        ..color = SeenlyPalette.paper.withOpacity(isCurrent ? 0.4 * pulse : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(nodes[i], glowR, glow);
      final core = Paint()..color = SeenlyPalette.paper.withOpacity(isCurrent ? 0.95 : 0.65);
      canvas.drawCircle(nodes[i], isCurrent ? 2.6 : 1.7, core);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.twinkle != twinkle || oldDelegate.nodeCount != nodeCount;
}

class _StarfieldBackdrop extends StatefulWidget {
  const _StarfieldBackdrop();

  @override
  State<_StarfieldBackdrop> createState() => _StarfieldBackdropState();
}

class _StarfieldBackdropState extends State<_StarfieldBackdrop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _StarfieldPainter(t: _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final double t;
  const _StarfieldPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(11);
    final paint = Paint()..style = PaintingStyle.fill;
    const tints = [SeenlyPalette.mustard, SeenlyPalette.coral, SeenlyPalette.periwinkle, SeenlyPalette.pink];
    for (int i = 0; i < 58; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = 0.6 + rnd.nextDouble() * 1.3;
      final phase = rnd.nextDouble();
      final twinkle = 0.14 + 0.58 * (0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi));
      final tinted = i % 7 == 0;
      paint.color = tinted ? tints[i % tints.length].withOpacity(twinkle * 0.9) : Colors.white.withOpacity(twinkle);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => oldDelegate.t != t;
}

class _Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const _Eyebrow(this.text, {this.color});
  @override
  Widget build(BuildContext context) {
    final resolved = color ?? _CardTone.of(context).fgMuted;
    return Text(text.toUpperCase(), style: SeenlyText.mono(size: 12, color: resolved, weight: FontWeight.w600));
  }
}

class _ShareButton extends StatelessWidget {
  final String label;
  final String shareText;
  const _ShareButton({required this.label, required this.shareText});

  @override
  Widget build(BuildContext context) {
    // Cards are now full-bleed color themselves, so a button that's
    // always accent-on-accent would vanish on the accent-background
    // cards. Instead: solid ink or solid paper, whichever contrasts with
    // this card's own foreground, so it reads as a real button on every
    // color in the deck.
    final tone = _CardTone.of(context);
    final onDark = tone.fg == SeenlyPalette.paper;
    final bg = onDark ? SeenlyPalette.paper : SeenlyPalette.ink;
    final fg = onDark ? SeenlyPalette.ink : SeenlyPalette.paper;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Share.share(shareText),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label, style: SeenlyText.mono(size: 12, color: fg, weight: FontWeight.w700)),
      ),
    );
  }
}

class _PosterThumb extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final bool elevated;
  const _PosterThumb({required this.url, this.width = 56, this.height = 82, this.elevated = false});

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: width,
        height: height,
        child: (url == null || url!.isEmpty)
            ? Container(
                color: SeenlyPalette.cork,
                child: const Icon(Icons.local_movies_outlined, size: 18, color: SeenlyPalette.inkFaint),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: SeenlyPalette.cork,
                  child: const Icon(Icons.local_movies_outlined, size: 18, color: SeenlyPalette.inkFaint),
                ),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : Container(color: SeenlyPalette.cork),
              ),
      ),
    );
    if (!elevated) return image;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), boxShadow: SeenlyPalette.softShadow),
      child: image,
    );
  }
}

/// A quiet row of poster thumbnails from the period's own entries — pure
/// decoration for cards that would otherwise be mostly empty space.
/// Renders nothing when the period has no posters on file.

// ---------------------------------------------------------------------------
// Illustrations — small, reusable, hand-built graphics standing in for the
// generic Material icons the previous pass used. Each one visualizes the
// specific stat it sits under rather than just decorating it.
// ---------------------------------------------------------------------------

/// A GitHub-contributions-style texture standing in for "your year" —
/// deterministic per [seed] (not re-randomized on every rebuild) so it
/// doesn't flicker as the person swipes back and forth.
class _YearGrid extends StatefulWidget {
  final int seed;
  final Color color;
  final int columns;
  const _YearGrid({required this.seed, required this.color, this.columns = 18});

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(widget.seed == 0 ? 1 : widget.seed);
    final cells = List.generate(54, (_) => rnd.nextDouble());
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.columns,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemBuilder: (context, i) {
            final v = cells[i];
            final target = v > .82 ? 1.0 : v > .6 ? .62 : v > .35 ? .34 : .14;
            // Cells light up one after another rather than all at once —
            // a soft "filling in the year" sweep instead of a hard pop.
            final delay = i / cells.length;
            final local = ((_controller.value - delay * 0.6) / 0.4).clamp(0.0, 1.0);
            return DecoratedBox(
              decoration: BoxDecoration(color: widget.color.withOpacity(target * local), borderRadius: BorderRadius.circular(2)),
            );
          },
        );
      },
    );
  }
}

/// Sweeps an `_ArcPainter` ring in from empty to [target] the first time
/// it's built, instead of appearing already fully drawn.
class _AnimatedRing extends StatelessWidget {
  final double target;
  final Color color;
  final Color backgroundColor;
  final double size;
  final double strokeWidth;
  const _AnimatedRing({
    required this.target,
    required this.color,
    required this.backgroundColor,
    required this.size,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => CustomPaint(
        size: Size(size, size),
        painter: _ArcPainter(values: [v], colors: [color], backgroundColor: backgroundColor, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// A little clapperboard — stands in for "total sessions" the way a ticket
/// stub or reel would in a physical scrapbook.
class _ClapperIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _ClapperIcon({required this.color, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.62,
      child: CustomPaint(painter: _ClapperPainter(color)),
    );
  }
}

class _ClapperPainter extends CustomPainter {
  final Color color;
  _ClapperPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final w = size.width, h = size.height;
    // body
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * 0.34, w, h * 0.66), const Radius.circular(4));
    canvas.drawRRect(body, fill);
    // clapper bar, filled then striped with clipped diagonal wedges
    final barRect = Rect.fromLTWH(0, 0, w, h * 0.32);
    final barRRect = RRect.fromRectAndRadius(barRect, const Radius.circular(3));
    canvas.save();
    canvas.clipRRect(barRRect);
    canvas.drawRect(barRect, fill);
    final stripeWidth = w / 7;
    for (var i = -1; i < 8; i++) {
      if (i.isOdd) continue;
      final x = i * stripeWidth;
      final path = Path()
        ..moveTo(x + h * 0.32, 0)
        ..lineTo(x + h * 0.32 + stripeWidth, 0)
        ..lineTo(x + stripeWidth, h * 0.32)
        ..lineTo(x, h * 0.32)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);
    }
    canvas.restore();
    // record dot
    canvas.drawCircle(Offset(w * 0.5, h * 0.68), h * 0.16, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.68),
      h * 0.16,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawCircle(Offset(w * 0.5, h * 0.68), h * 0.05, fill);
  }

  @override
  bool shouldRepaint(covariant _ClapperPainter oldDelegate) => oldDelegate.color != color;
}

/// A dark "LED" panel, digits lit up — the literal digital clock the
/// person asked for, standing in for the plain arc + number the previous
/// pass used.
class _DigitalClock extends StatelessWidget {
  final String time;
  const _DigitalClock({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A322C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A241F), width: 3),
      ),
      child: Text(
        time,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF0C878),
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// A dawn→day→dusk→night gradient strip with a marker pinned at the
/// person's peak viewing hour — literal "where in the day" context for
/// the digital clock above it.
class _DayGradientBar extends StatefulWidget {
  final double hourFraction; // 0..1 across a 24h day
  const _DayGradientBar({required this.hourFraction});

  @override
  State<_DayGradientBar> createState() => _DayGradientBarState();
}

class _DayGradientBarState extends State<_DayGradientBar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 12,
              margin: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(colors: [
                  Color(0xFFF0C878),
                  Color(0xFF8FB3D9),
                  Color(0xFF8FB3D9),
                  Color(0xFFD8895A),
                  Color(0xFF3A322C),
                ], stops: [
                  0.0,
                  0.22,
                  0.55,
                  0.75,
                  0.92,
                ]),
              ),
            ),
            Positioned(
              left: (w * widget.hourFraction.clamp(0.0, 1.0) - 11).clamp(0.0, w - 22),
              top: -1,
              // Same slow, soft breathing scale as the archetype badge —
              // marks "this is you, right now" on the day scale without
              // demanding attention.
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final scale = 1 + Curves.easeInOut.transform(_controller.value) * 0.12;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeenlyPalette.ink,
                    border: Border.all(color: const Color(0xFFF0C878), width: 3),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// A literal filmstrip — sprocket holes down each side, colored frames
/// standing in for genre share, instead of a plain proportional bar.
class _FilmStrip extends StatelessWidget {
  final List<double> weights;
  final List<Color> colors;
  const _FilmStrip({required this.weights, required this.colors});

  @override
  Widget build(BuildContext context) {
    Widget sprockets() => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (_) => Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: SeenlyPalette.ink.withOpacity(0.55), borderRadius: BorderRadius.circular(1)),
              )),
        );
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFF241B16), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          sprockets(),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Row(
                children: [
                  for (var i = 0; i < weights.length; i++)
                    Expanded(
                      flex: (weights[i] * 1000).round().clamp(1, 100000),
                      child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), color: colors[i % colors.length]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          sprockets(),
        ],
      ),
    );
  }
}

/// Two little person silhouettes — one solid, one faint duo — standing in
/// for "watched alone" vs "watched with someone", literal rather than a
/// plain color-key dot.
class _FigureIcon extends StatelessWidget {
  final bool duo;
  final Color color;
  final double opacity;
  const _FigureIcon({required this.duo, required this.color, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    Widget person() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: color.withOpacity(opacity), shape: BoxShape.circle)),
            const SizedBox(height: 2),
            Container(
              width: 22,
              height: 15,
              decoration: BoxDecoration(color: color.withOpacity(opacity), borderRadius: BorderRadius.circular(8)),
            ),
          ],
        );
    if (!duo) return person();
    return Row(mainAxisSize: MainAxisSize.min, children: [person(), const SizedBox(width: 4), person()]);
  }
}

/// A simple two-pan balance scale — literal "which side of the year was
/// heavier", standing in for a plain side-by-side stat pair.
class _BalanceScale extends StatelessWidget {
  final int leftValue;
  final int rightValue;
  final String leftLabel;
  final String rightLabel;
  final Color color;
  const _BalanceScale({
    required this.leftValue,
    required this.rightValue,
    required this.leftLabel,
    required this.rightLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final total = (leftValue + rightValue).clamp(1, 1 << 30);
    final tilt = ((rightValue - leftValue) / total).clamp(-0.35, 0.35).toDouble();
    return TweenAnimationBuilder<double>(
      // Settles from level (0) to its final tilt on entrance, the way a
      // real scale would gently find its balance rather than starting
      // already tipped.
      tween: Tween(begin: 0, end: tilt),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, animatedTilt, _) => SizedBox(
        height: 128,
        child: CustomPaint(
          painter: _ScalePainter(tilt: animatedTilt, color: color),
          child: Padding(
            padding: const EdgeInsets.only(top: 78),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _scaleLabel('$leftValue', leftLabel),
                _scaleLabel('$rightValue', rightLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scaleLabel(String value, String label) => Column(
        children: [
          Text(value, style: SeenlyText.serif(size: 18, weight: FontWeight.w700, color: color)),
          Text(label, style: SeenlyText.mono(size: 10, color: color.withOpacity(.72))),
        ],
      );
}

class _ScalePainter extends CustomPainter {
  final double tilt; // -1..1, positive tilts right side down
  final Color color;
  _ScalePainter({required this.tilt, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final centerX = size.width / 2;
    const postTop = 10.0;
    const beamY = 36.0;
    canvas.drawLine(Offset(centerX, postTop), Offset(centerX, beamY + 10), paint);
    canvas.drawCircle(Offset(centerX, postTop - 2), 4, Paint()..color = color);
    final dy = tilt * 16;
    final leftEnd = Offset(centerX - 60, beamY - dy);
    final rightEnd = Offset(centerX + 60, beamY + dy);
    canvas.drawLine(leftEnd, rightEnd, paint);
    canvas.drawLine(Offset(centerX, beamY), leftEnd, paint..strokeWidth = 2);
    canvas.drawLine(Offset(centerX, beamY), rightEnd, paint);
    _pan(canvas, leftEnd, color);
    _pan(canvas, rightEnd, color);
  }

  void _pan(Canvas canvas, Offset top, Color color) {
    final panCenter = Offset(top.dx, top.dy + 26);
    final rect = Rect.fromCenter(center: panCenter, width: 48, height: 24);
    final path = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.center.dx, rect.bottom)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.top)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(top, Offset(rect.left, rect.top), Paint()..color = color..strokeWidth = 1.6);
    canvas.drawLine(top, Offset(rect.right, rect.top), Paint()..color = color..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _ScalePainter oldDelegate) => oldDelegate.tilt != tilt || oldDelegate.color != color;
}

/// A five-point star ribbon badge — generic enough to sit under any
/// archetype label (which comes from the backend as free text, not a
/// fixed set), unlike a literal illustration tied to one specific label.
class _BadgeIcon extends StatefulWidget {
  final Color color;
  final double size;
  const _BadgeIcon({required this.color, this.size = 78});

  @override
  State<_BadgeIcon> createState() => _BadgeIconState();
}

class _BadgeIconState extends State<_BadgeIcon> with SingleTickerProviderStateMixin {
  // A slow, soft breathing scale — small enough (±3%) that it reads as
  // "quietly alive" rather than a bouncing animation competing for
  // attention. Same duration family as the constellation's twinkle
  // (2600ms) so the deck's ambient motion feels like one shared tempo.
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1 + Curves.easeInOut.transform(_controller.value) * 0.035;
        return Transform.scale(scale: scale, child: child);
      },
      child: SizedBox(width: widget.size, height: widget.size * 1.18, child: CustomPaint(painter: _BadgePainter(widget.color))),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final Color color;
  _BadgePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = color;
    // ribbon tails
    final tailL = Path()
      ..moveTo(w * 0.32, h * 0.62)
      ..lineTo(w * 0.14, h)
      ..lineTo(w * 0.4, h * 0.86)
      ..close();
    final tailR = Path()
      ..moveTo(w * 0.68, h * 0.62)
      ..lineTo(w * 0.86, h)
      ..lineTo(w * 0.6, h * 0.86)
      ..close();
    canvas.drawPath(tailL, fill);
    canvas.drawPath(tailR, fill);
    // circle medallion
    final center = Offset(w * 0.5, h * 0.4);
    canvas.drawCircle(center, w * 0.4, fill);
    // star cutout
    final starPaint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear;
    canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint());
    canvas.drawCircle(center, w * 0.4, fill);
    final starPath = _starPath(center, w * 0.22, w * 0.09, 5);
    canvas.drawPath(starPath, starPaint);
    canvas.restore();
  }

  Path _starPath(Offset center, double outerR, double innerR, int points) {
    final path = Path();
    final step = math.pi / points;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = -math.pi / 2 + i * step;
      final p = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _BadgePainter oldDelegate) => oldDelegate.color != color;
}

/// A dashed route between two poster stubs, with small pin markers at each
/// end — the literal "path travelled through the year" for the first/last
/// screen.
class _RoutePainter extends CustomPainter {
  final Color color;
  _RoutePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.75)
      ..cubicTo(
        size.width * 0.5, size.height * 0.9,
        size.width * 0.55, size.height * 0.15,
        size.width * 0.82, size.height * 0.3,
      );
    final dashed = _dashPath(path, 4, 5);
    canvas.drawPath(dashed, paint);
    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.75), 3.4, Paint()..color = color);
    canvas.drawCircle(Offset(size.width * 0.82, size.height * 0.3), 3.4, Paint()..color = color);
  }

  Path _dashPath(Path source, double dash, double gap) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dash : gap;
        final next = (distance + len).clamp(0.0, metric.length);
        if (draw) dest.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.color != color;
}

/// An envelope with a little wax-seal checkmark for the Letter card
/// footer — smaller and simpler than the opening-screen `_EnvelopePainter`
/// above (kept separate rather than reused since that one is tuned for a
/// big centered tap target, this one for a small inline mark).
class _LetterSealIcon extends StatelessWidget {
  final Color paperColor;
  final Color inkColor;
  final Color sealColor;
  const _LetterSealIcon({required this.paperColor, required this.inkColor, required this.sealColor});

  @override
  Widget build(BuildContext context) => SizedBox(width: 108, height: 80, child: CustomPaint(painter: _LetterSealPainter(paperColor, inkColor, sealColor)));
}

class _LetterSealPainter extends CustomPainter {
  final Color paperColor;
  final Color inkColor;
  final Color sealColor;
  _LetterSealPainter(this.paperColor, this.inkColor, this.sealColor);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8));
    canvas.drawRRect(body, Paint()..color = paperColor);
    final flap = Path()
      ..moveTo(0, 0)
      ..lineTo(w / 2, h * 0.56)
      ..lineTo(w, 0);
    canvas.drawPath(flap, Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round);
    final sealCenter = Offset(w / 2, h * 0.56);
    canvas.drawCircle(sealCenter, h * 0.16, Paint()..color = sealColor);
    final check = Path()
      ..moveTo(sealCenter.dx - 6, sealCenter.dy)
      ..lineTo(sealCenter.dx - 1, sealCenter.dy + 5)
      ..lineTo(sealCenter.dx + 7, sealCenter.dy - 7);
    canvas.drawPath(check, Paint()
      ..color = paperColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _LetterSealPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Chapter 1 — overview (single full-width cards)
// ---------------------------------------------------------------------------

class _OverviewSessionsCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _OverviewSessionsCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      bonusLabel: 'экран 1 из 3',
      onNext: onNext,
      background: SeenlyPalette.accent,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ClapperIcon(color: fg),
            const SizedBox(height: 16),
            _Eyebrow(summary.scope == 'all' ? 'твоё кино за всё время' : 'твой ${summary.periodLabel} в кино'),
            const SizedBox(height: 6),
            _CountUp(value: summary.totalLogged, style: SeenlyText.serif(size: 64, weight: FontWeight.w700, color: fg)),
            Text(_overviewSubtitle(summary), style: SeenlyText.serif(size: 16, weight: FontWeight.w500, color: fg)),
            const SizedBox(height: 18),
            SizedBox(width: 200, child: _YearGrid(seed: summary.totalLogged, color: fg)),
            const SizedBox(height: 18),
            const _TicketDash(),
            const SizedBox(height: 14),
            Text(
              'это ${_hoursLabel(summary.totalHours)} за экраном — примерно каждый ${_roughlyEveryNth(summary)}-й вечер ${_periodPossessive(summary)} начинался с тебя и экрана',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _equivChip('≈ ${(summary.totalHours / 24).round()} суток', fg),
                _equivChip('≈ ${_workDaysEquivalent(summary.totalHours)} раб. дней', fg),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _equivChip(String text, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: fg.withOpacity(0.45)), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: SeenlyText.mono(size: 11, color: fg, weight: FontWeight.w600)),
    );
  }
}

// Playful real-world equivalents for the total screen-time hours — not
// exact conversions, just relatable ballpark comparisons the way a
// "wrapped" recap uses ("that's N marathons", "M cross-country trips").
int _trainKmEquivalent(double totalHours) => (totalHours * 80).round(); // ~80 км/ч, средний интерсити
int _workDaysEquivalent(double totalHours) => (totalHours / 8).round(); // 8-часовой рабочий день

String _formatThousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _periodPossessive(WrappedSummary s) {
  switch (s.scope) {
    case 'month':
      return 'этого месяца';
    case 'all':
      return 'за всё это время';
    default:
      return 'этого года';
  }
}

int _roughlyEveryNth(WrappedSummary s) {
  if (s.totalLogged == 0) return 365;
  final periodDays = _periodDaysFor(s);
  final n = (periodDays / s.totalLogged).round();
  return n < 1 ? 1 : n;
}

int _periodDaysFor(WrappedSummary s) {
  if (s.scope == 'month' && s.month != null) {
    return DateTime(s.year, s.month! + 1, 0).day;
  }
  if (s.scope == 'all') {
    return s.daysSpan > 0 ? s.daysSpan : 1;
  }
  return 365;
}

String _hoursLabel(double totalHours) {
  final totalMinutes = (totalHours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return '$h ч ${m.toString().padLeft(2, '0')} мин';
}

/// Russian plural form picker (1 день / 2 дня / 5 дней, etc.) — Russian
/// noun endings depend on the last digit *and* whether the number falls
/// in the 11-14 "always many" exception band, not just singular/plural.
String _pluralRu(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  switch (n % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

String _daysLabel(int n) => '$n ${_pluralRu(n, 'день', 'дня', 'дней')}';
String _sessionsWord(int n) => _pluralRu(n, 'сеанс', 'сеанса', 'сеансов');

String _overviewSubtitle(WrappedSummary s) {
  final word = _sessionsWord(s.totalLogged);
  switch (s.scope) {
    case 'month':
      return '$word за месяц';
    case 'all':
      return '$word за всё время';
    default:
      return '$word за год';
  }
}

class _ClockCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _ClockCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final hour = summary.peakHour;
    return _CardShell(
      bonusLabel: 'экран 2 из 3',
      onNext: onNext,
      background: SeenlyPalette.mustard,
      light: false,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('когда ты смотришь'),
            const SizedBox(height: 6),
            Text('твой киночас', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 26),
            _DigitalClock(time: hour != null ? '${hour.toString().padLeft(2, '0')}:00' : '--:--'),
            const SizedBox(height: 20),
            SizedBox(width: 200, child: _DayGradientBar(hourFraction: (hour ?? 12) / 24)),
            const SizedBox(height: 10),
            if (hour != null)
              Text(_dayPartLabel(hour), style: SeenlyText.mono(size: 12, color: fg, weight: FontWeight.w700)),
            const SizedBox(height: 20),
            const _TicketDash(),
            const SizedBox(height: 14),
            Text(
              hour != null
                  ? 'около ${summary.peakHourPercent.round()}% фильмов начаты в пределах часа от ${hour.toString().padLeft(2, '0')}:00'
                  : 'пока недостаточно данных о времени просмотра',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.78)),
            ),
          ],
        );
      }),
    );
  }
}

String _dayPartLabel(int hour) {
  if (hour >= 0 && hour < 6) return 'глубокая ночь';
  if (hour < 12) return 'утро';
  if (hour < 18) return 'день';
  if (hour < 23) return 'вечер';
  return 'поздний вечер';
}

class _GenreStripCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _GenreStripCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final mix = summary.genreMix;
    return _CardShell(
      bonusLabel: 'экран 3 из 3',
      onNext: onNext,
      background: SeenlyPalette.coral,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('из чего состоял год'),
            const SizedBox(height: 6),
            Text('твоя плёнка', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 22),
            if (mix.isNotEmpty) ...[
              SizedBox(
                width: 220,
                child: _FilmStrip(
                  weights: [for (final g in mix) g.percent / 100 + 0.02],
                  colors: [for (int i = 0; i < mix.length; i++) _genreColor(i)],
                ),
              ),
              const SizedBox(height: 22),
              for (int i = 0; i < mix.length; i++)
                _StaggerFade(
                  index: i,
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: _genreColor(i), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(mix[i].genre, style: SeenlyText.serif(size: 14, weight: FontWeight.w500, color: fg))),
                      Text('${mix[i].percent.round()}%', style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.7))),
                    ],
                  ),
                  ),
                ),
            ] else
              Text('пока недостаточно жанров для картины',
                  textAlign: TextAlign.center, style: SeenlyText.serif(color: fg.withOpacity(0.8))),
          ],
        );
      }),
    );
  }
}

Color _genreColor(int i) => SeenlyPalette.gridColorFor(i);

// ---------------------------------------------------------------------------
// Chapter 2 — habits (8 individual full-screen cards)
// ---------------------------------------------------------------------------

class _FirstLastCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _FirstLastCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final first = summary.first;
    final last = summary.last;
    return _CardShell(
      bonusLabel: 'экран 1 из 8',
      onNext: onNext,
      background: SeenlyPalette.sage,
      light: false,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('старт и финиш'),
            const SizedBox(height: 6),
            Text('первый и последний', style: SeenlyText.serif(size: 18, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: CustomPaint(painter: _RoutePainter(fg.withOpacity(0.7)), child: const SizedBox.expand()),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (first != null) Expanded(child: _bookendColumn(first.dateLabel, first.title, first.posterUrl, fg)),
                if (last != null) Expanded(child: _bookendColumn(last.dateLabel, last.title, last.posterUrl, fg)),
              ],
            ),
            const SizedBox(height: 22),
            const _TicketDash(),
            const SizedBox(height: 14),
            Text('${_daysLabel(summary.daysSpan)} между первым и последним кадром',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8))),
          ],
        );
      }),
    );
  }

  Widget _bookendColumn(String date, String title, String? posterUrl, Color fg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PosterThumb(url: posterUrl, width: 96, height: 140, elevated: true),
        const SizedBox(height: 10),
        Text(date, style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.7))),
        const SizedBox(height: 2),
        Text(title,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12, weight: FontWeight.w600, color: fg),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _DirectorsCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _DirectorsCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final directors = summary.topDirectors;
    return _CardShell(
      bonusLabel: 'экран 2 из 8',
      onNext: onNext,
      background: SeenlyPalette.clay,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('режиссёры года'),
            const SizedBox(height: 6),
            Text('твой топ-${directors.length.clamp(1, 4)}', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 24),
            if (directors.isEmpty)
              Text('пока не хватает данных', style: SeenlyText.mono(size: 12, color: fg.withOpacity(0.6)))
            else
              SizedBox(
                width: 230,
                child: Column(
                  children: [
                    for (int i = 0; i < directors.length; i++)
                      _StaggerFade(
                        index: i,
                        child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: fg.withOpacity(i == 0 ? 0.9 : 0.28 - i * 0.05),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: Text('${i + 1}',
                                  style: SeenlyText.serif(
                                      size: 12, weight: FontWeight.w700, color: i == 0 ? SeenlyPalette.clay : fg)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(directors[i].name,
                                  style: SeenlyText.serif(size: 14, weight: FontWeight.w600, color: fg),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Text('×${directors[i].count}', style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.7))),
                          ],
                        ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const _TicketDash(),
            const SizedBox(height: 12),
            Text('режиссёры, к которым ты возвращалась чаще всего',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 12, color: fg.withOpacity(0.75))),
          ],
        );
      }),
    );
  }
}

class _DecadeCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _DecadeCard({required this.summary, required this.onNext});

  static const _labelRu = {'2020s': '2020-е', '2010s': '2010-е', 'older': 'до 2010-х'};

  @override
  Widget build(BuildContext context) {
    final decades = summary.decades;
    final topLabel = decades.isNotEmpty ? _labelRu[decades.first.label] ?? decades.first.label : null;
    final maxPercent = decades.isEmpty ? 1.0 : decades.map((d) => d.percent).reduce(math.max);
    return _CardShell(
      bonusLabel: 'экран 3 из 8',
      onNext: onNext,
      background: SeenlyPalette.pink,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('из какого времени твои фильмы'),
            const SizedBox(height: 6),
            Text(topLabel != null ? 'в основном $topLabel' : '—', style: SeenlyText.serif(size: 21, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 26),
            if (decades.isNotEmpty) ...[
              SizedBox(
                height: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < decades.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: SizedBox(
                          width: 26,
                          child: _GrowBar(
                            height: math.max(14, 88 * (decades[i].percent / maxPercent)),
                            delay: decades.length <= 1 ? 0 : i / (decades.length - 1),
                            color: i == 0 ? fg : fg.withOpacity(0.32),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < decades.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: SizedBox(
                        width: 26,
                        child: Text(
                          _labelRu[decades[i].label] ?? decades[i].label,
                          textAlign: TextAlign.center,
                          style: SeenlyText.mono(size: 8, color: fg.withOpacity(i == 0 ? 1 : 0.65), weight: i == 0 ? FontWeight.w700 : FontWeight.w400),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const _TicketDash(),
              const SizedBox(height: 12),
              Text('${decades.first.percent.round()}% фильмов из этого времени',
                  textAlign: TextAlign.center, style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8))),
            ],
          ],
        );
      }),
    );
  }
}

class _NewVsRewatchCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _NewVsRewatchCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      bonusLabel: 'экран 4 из 8',
      onNext: onNext,
      background: SeenlyPalette.cork,
      light: false,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        final more = summary.newCount >= summary.rewatchCount ? 'открытий' : 'пересмотров';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('новое или знакомое'),
            const SizedBox(height: 6),
            Text('баланс года', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 6),
            _BalanceScale(
              leftValue: summary.newCount,
              rightValue: summary.rewatchCount,
              leftLabel: 'новых',
              rightLabel: 'пересмотров',
              color: fg,
            ),
            const SizedBox(height: 10),
            const _TicketDash(),
            const SizedBox(height: 14),
            Text('чуть больше половины года — $more',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.78))),
          ],
        );
      }),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _TimelineCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final buckets = summary.timeline;
    final maxCount = buckets.isEmpty ? 0 : buckets.map((b) => b.count).reduce(math.max);
    final isMonth = summary.scope == 'month';
    return _CardShell(
      bonusLabel: 'экран 5 из 8',
      onNext: onNext,
      background: SeenlyPalette.periwinkle,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow(isMonth ? 'самый плотный день' : 'месяц года'),
            const SizedBox(height: 6),
            Text(summary.busiestTimelineLabel ?? '—', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 22),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < buckets.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isMonth ? 1 : 2.5),
                        child: _GrowBar(
                          height: maxCount == 0 ? 3 : (4 + (buckets[i].count / maxCount) * 112),
                          delay: buckets.length <= 1 ? 0 : i / (buckets.length - 1),
                          color: buckets[i].count == 0
                              ? fg.withOpacity(0.15)
                              : (buckets[i].count == maxCount ? fg : fg.withOpacity(0.4)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!isMonth) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final b in buckets)
                    Expanded(
                      child: Center(
                        // FittedBox instead of a plain Text: with 12 columns the
                        // available width per label is only ~25-28px, and some
                        // month abbreviations were wide enough to wrap onto a
                        // second line, breaking the whole row's alignment. This
                        // guarantees every label stays on one line, shrinking
                        // slightly instead of wrapping.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            b.label,
                            maxLines: 1,
                            softWrap: false,
                            style: SeenlyText.mono(size: 12, color: fg.withOpacity(0.6)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const _TicketDash(),
            const SizedBox(height: 12),
            Text('${_daysLabel(summary.longestStreakDays)} подряд — твой самый длинный стрик',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8))),
          ],
        );
      }),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _WeekdayCard({required this.summary, required this.onNext});

  static const _labels = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

  @override
  Widget build(BuildContext context) {
    final weekdays = summary.weekdays;
    final maxCount = weekdays.isEmpty ? 0 : weekdays.map((d) => d.count).reduce(math.max);
    return _CardShell(
      bonusLabel: 'экран 6 из 8',
      onNext: onNext,
      background: SeenlyPalette.mustard,
      light: false,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('какой день — твой'),
            const SizedBox(height: 6),
            Text('${summary.weekendPercent.round()}% на выходных',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 22),
            SizedBox(
              height: 116,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < weekdays.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: _GrowBar(
                          height: maxCount == 0 ? 3 : (4 + (weekdays[i].count / maxCount) * 104),
                          delay: weekdays.length <= 1 ? 0 : i / (weekdays.length - 1),
                          color: (i == 5 || i == 6) && weekdays[i].count > 0 ? fg : fg.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (int i = 0; i < _labels.length; i++)
                  Expanded(
                    child: Center(
                      child: Text(_labels[i],
                          style: SeenlyText.mono(
                              size: 11,
                              color: (i == 5 || i == 6) ? fg : fg.withOpacity(0.55),
                              weight: (i == 5 || i == 6) ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _TicketDash(),
            const SizedBox(height: 12),
            Text('суббота и воскресенье — твои главные киновечера',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8))),
          ],
        );
      }),
    );
  }
}

class _SoloCompanyCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _SoloCompanyCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      bonusLabel: 'экран 7 из 8',
      onNext: onNext,
      background: SeenlyPalette.periwinkle,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Eyebrow('как ты смотрела'),
            const SizedBox(height: 6),
            Text('соло или компания', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: fg)),
            const SizedBox(height: 20),
            SizedBox(
              width: 168,
              height: 168,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _AnimatedRing(target: summary.soloPercent / 100, color: fg, backgroundColor: fg.withOpacity(0.22), size: 168, strokeWidth: 15),
                  Text('${summary.soloPercent.round()}%', style: SeenlyText.serif(size: 30, weight: FontWeight.w700, color: fg)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    _FigureIcon(duo: false, color: fg),
                    const SizedBox(height: 6),
                    Text('${summary.soloCount} · одна', style: SeenlyText.mono(size: 11, color: fg)),
                  ],
                ),
                const SizedBox(width: 24),
                Column(
                  children: [
                    _FigureIcon(duo: true, color: fg, opacity: 0.65),
                    const SizedBox(height: 6),
                    Text('${summary.companyCount} · с кем-то', style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.85))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _TicketDash(),
            const SizedBox(height: 12),
            Text('почти две трети сеансов — в одиночку',
                textAlign: TextAlign.center, style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.8))),
          ],
        );
      }),
    );
  }
}

class _ArchetypeCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _ArchetypeCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final peak = summary.peakHour;
    return _CardShell(
      bonusLabel: 'экран 8 из 8',
      onNext: onNext,
      background: SeenlyPalette.accent,
      shareButton: _ShareButton(
        label: 'поделиться типажом →',
        shareText: 'мой типаж года в teamira: ${summary.archetypeLabel}',
      ),
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BadgeIcon(color: fg),
            const SizedBox(height: 8),
            _Eyebrow('твой типаж года'),
            const SizedBox(height: 6),
            Text(summary.archetypeLabel,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 26, weight: FontWeight.w700, color: fg),
                maxLines: 3),
            const SizedBox(height: 6),
            Text(
              'основано на ${summary.totalLogged} записях за ${summary.periodLabel}',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: fg.withOpacity(0.75)),
            ),
            const SizedBox(height: 18),
            const _TicketDash(),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (peak != null) _chip('пик в ${peak.toString().padLeft(2, '0')}:00', fg),
                _chip(summary.soloPercent >= 50 ? 'чаще всего одна' : 'чаще всего с кем-то', fg),
                if (summary.topGenre != null) _chip('любимый жанр — ${summary.topGenre}', fg),
                _chip('стрик — ${summary.longestStreakDays} дней', fg),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _chip(String text, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(border: Border.all(color: fg.withOpacity(0.4)), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: SeenlyText.mono(size: 11, color: fg, weight: FontWeight.w600)),
    );
  }
}

/// A read-only heart row that respects the current card's foreground
/// instead of `HeartRating`'s fixed rating-color gradient — that gradient
/// is tuned for hearts sitting on the app's usual paper background, and
/// would lose contrast (or clash) against these cards' own saturated
/// full-bleed colors.
class _ToneHearts extends StatelessWidget {
  final int value;
  final int max;
  final double size;
  const _ToneHearts({required this.value, this.max = 10, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final fg = _CardTone.of(context).fg;
    return Wrap(
      spacing: 2,
      children: [
        for (var i = 1; i <= max; i++)
          Icon(i <= value ? Icons.favorite : Icons.favorite_border, size: size, color: i <= value ? fg : fg.withOpacity(0.35)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter 3 — reviews
// ---------------------------------------------------------------------------

class _ReviewsOverviewCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _ReviewsOverviewCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final pagesInChapter = summary.favoriteReview != null ? 2 : 1;
    final headerPoster = summary.favoriteReview?.posterUrl ??
        (summary.topReviews.isNotEmpty ? summary.topReviews.first.posterUrl : null);
    return _CardShell(
      bonusLabel: 'экран 1 из $pagesInChapter',
      onNext: onNext,
      background: SeenlyPalette.coral,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PosterThumb(url: headerPoster, width: 64, height: 92, elevated: true),
            const SizedBox(height: 16),
            _Eyebrow('твои рецензии'),
            _CountUp(value: summary.reviewCount, style: SeenlyText.serif(size: 46, weight: FontWeight.w700, color: fg)),
            Text('фильма получили оценку', style: SeenlyText.serif(size: 14, weight: FontWeight.w500, color: fg)),
            const SizedBox(height: 10),
            Text(
              'средняя оценка ${summary.averageRating.toStringAsFixed(1)} · ${summary.fullMarksCount} полных пятёрок',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: fg.withOpacity(0.78)),
            ),
            const SizedBox(height: 18),
            const _TicketDash(),
            const SizedBox(height: 16),
            for (int i = 0; i < summary.topReviews.length; i++)
              _StaggerFade(
                index: i,
                child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    _PosterThumb(url: summary.topReviews[i].posterUrl, width: 34, height: 50),
                    const SizedBox(width: 12),
                    Expanded(child: Text(summary.topReviews[i].title, style: SeenlyText.serif(size: 13, weight: FontWeight.w500, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (summary.topReviews[i].rating != null)
                      _ToneHearts(value: summary.topReviews[i].rating!)
                    else
                      Text('—', style: SeenlyText.mono(size: 12, color: fg.withOpacity(0.5))),
                  ],
                ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _FavoriteReviewCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _FavoriteReviewCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final r = summary.favoriteReview!;
    final hasNote = r.note != null && r.note!.trim().isNotEmpty;
    return _CardShell(
      bonusLabel: 'экран 2 из 2',
      onNext: onNext,
      background: SeenlyPalette.pink,
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PosterThumb(url: r.posterUrl, width: 100, height: 146, elevated: true),
            const SizedBox(height: 16),
            _Eyebrow('рецензия · ${r.dateLabel ?? ''}'),
            const SizedBox(height: 6),
            Text(r.title, style: SeenlyText.serif(size: 19, weight: FontWeight.w700, color: fg), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            if (r.rating != null)
              Center(child: _ToneHearts(value: r.rating!, size: 15))
            else
              Text('—', textAlign: TextAlign.center, style: SeenlyText.serif(size: 16, color: fg)),
            if (hasNote) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border(left: BorderSide(color: fg, width: 3)),
                ),
                child: Text(
                  '«${r.note}»',
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: 13, color: fg),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _TicketDash(),
            const SizedBox(height: 12),
            Text('лучшая оценка периода',
                style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.85), weight: FontWeight.w700)),
          ],
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Letter
// ---------------------------------------------------------------------------

class _LetterCard extends StatelessWidget {
  final WrappedSummary summary;
  final VoidCallback onNext;
  const _LetterCard({required this.summary, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final letterText =
        'в дневнике за ${summary.periodLabel} появилось ${summary.totalLogged} записей, а на экране прошло '
        '${_hoursLabel(summary.totalHours)} — это примерно ${(summary.totalHours / 24).round()} суток, отданных чужим историям.\n\n'
        '${_genreShareSentence(summary)} '
        '${summary.busiestTimelineLabel != null ? (summary.scope == 'month' ? 'самым плотным был ${summary.busiestTimelineLabel}' : 'самым насыщенным месяцем был ${summary.busiestTimelineLabel}') : ''}'
        '${summary.longestStreakDays > 1 ? ', а самый длинный стрик — ${_daysLabel(summary.longestStreakDays)} подряд' : ''}.';

    return _CardShell(
      bonusLabel: 'письмо',
      onNext: onNext,
      background: SeenlyPalette.accent,
      shareButton: _ShareButton(
        label: 'поделиться письмом →',
        shareText: letterText,
      ),
      child: Builder(builder: (context) {
        final fg = _CardTone.of(context).fg;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _LetterSealIcon(paperColor: fg, inkColor: SeenlyPalette.accent, sealColor: SeenlyPalette.accent),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(summary.last?.dateLabel ?? '31 декабря, поздно вечером',
                  style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.7))),
            ),
            const SizedBox(height: 10),
            Text(letterText, style: SeenlyText.serif(size: 14, color: fg)),
            if (summary.favoriteReview?.note != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: fg, width: 2))),
                child: Text(
                  '«${summary.favoriteReview!.note}»\n— запись от ${summary.favoriteReview!.dateLabel ?? ''}',
                  style: SeenlyText.serif(size: 13, color: fg.withOpacity(0.85)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _TicketDash(),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Text('P.S.', style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.6)))),
            const SizedBox(height: 6),
            if (summary.topGenre != null) _LetterFactRow('жанр года', summary.topGenre!, fg),
            if (summary.topDirectors.isNotEmpty) _LetterFactRow('режиссёр года', summary.topDirectors.first.name, fg),
            _LetterFactRow('средняя оценка', summary.averageRating.toStringAsFixed(1), fg),
            if (summary.hoursPercentile != null)
              _LetterFactRow('место в топ', '${100 - summary.hoursPercentile!}%', fg),
          ],
        );
      }),
    );
  }
}

String _genreShareSentence(WrappedSummary s) {
  if (s.genreMix.isEmpty) return '';
  final top = s.genreMix.first;
  return '${top.genre[0].toUpperCase()}${top.genre.substring(1)} забрала ${top.percent.round()}% твоего года;';
}

class _LetterFactRow extends StatelessWidget {
  final String label;
  final String value;
  final Color fg;
  const _LetterFactRow(this.label, this.value, this.fg);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: SeenlyText.mono(size: 11, color: fg.withOpacity(0.65))),
          const Spacer(),
          Text(value, style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt
// ---------------------------------------------------------------------------

class _ReceiptCard extends StatelessWidget {
  final WrappedSummary summary;
  const _ReceiptCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final items = summary.receiptItems;
    final shown = items.take(4).toList();
    final rest = items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: LayoutBuilder(builder: (context, outer) {
        final floor = math.min(440.0, outer.maxHeight);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: outer.maxHeight),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: floor),
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                decoration: ShapeDecoration(
                  color: SeenlyPalette.paper,
                  shape: const _TicketNotchBorder(),
                  shadows: SeenlyPalette.softShadow,
                ),
                child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('TEAMIRA', style: SeenlyText.serif(size: 20, weight: FontWeight.w700, color: SeenlyPalette.ink))),
          const SizedBox(height: 4),
          Center(
            child: Text('чек · ${summary.rangeLabel}',
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
          ),
          const SizedBox(height: 14),
          const _ReceiptDivider(),
          const SizedBox(height: 10),
          Center(
            child: Text('${items.length} позиции'.toUpperCase(),
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          const _ReceiptDivider(),
          const SizedBox(height: 10),
          for (final it in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text(it.title, style: SeenlyText.bodyText, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('×${it.count}', style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
          if (rest > 0)
            Text('+ $rest других позиций', style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 10),
          const _ReceiptDivider(),
          const SizedBox(height: 10),
          Center(
            child: Text('скидки и бонусы'.toUpperCase(),
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          _ReceiptRow('стрик ${_daysLabel(summary.longestStreakDays)}', '+1 значок'),
          _ReceiptRow('пересмотр любимого', '×${summary.rewatchCount}'),
          const SizedBox(height: 8),
          const _ReceiptDivider(),
          const SizedBox(height: 10),
          _ReceiptRow('итого времени', _hoursLabel(summary.totalHours)),
          if (summary.topGenre != null) _ReceiptRow('любимый жанр', summary.topGenre!),
          const SizedBox(height: 10),
          const _ReceiptDivider(),
          const SizedBox(height: 14),
          Center(child: Text(
            summary.scope == 'month' ? 'спасибо за этот месяц ♥' : 'спасибо за этот год ♥',
            style: SeenlyText.serif(size: 14, color: SeenlyPalette.accent),
          )),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 160,
              height: 34,
              child: CustomPaint(painter: _BarcodePainter()),
            ),
          ),
          const SizedBox(height: 18),
          _ShareButton(
            label: 'поделиться чеком →',
            shareText:
                'мой год в teamira: ${summary.totalLogged} записей, ${_hoursLabel(summary.totalHours)} за экраном, любимый жанр — ${summary.topGenre ?? '—'}',
          ),
        ],
              ),
            ),
          ),
        ),
      );
      }),
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider();
  @override
  Widget build(BuildContext context) => Divider(color: SeenlyPalette.dashedBorder, height: 1);
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReceiptRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: SeenlyText.bodyText),
          const Spacer(),
          Text(value, style: SeenlyText.serif(size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SeenlyPalette.ink;
    final rnd = math.Random(7);
    double x = 0;
    while (x < size.width) {
      final w = 1.0 + rnd.nextInt(3);
      if (rnd.nextBool()) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      }
      x += w + 1.5;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Shared arc painter (clock + solo/company donuts)
// ---------------------------------------------------------------------------

class _ArcPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color backgroundColor;
  final double strokeWidth;

  const _ArcPainter({
    required this.values,
    required this.colors,
    this.backgroundColor = SeenlyPalette.background,
    this.strokeWidth = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

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
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
