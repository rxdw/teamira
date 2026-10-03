import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';

import '../../models/profile_stats.dart';
import '../../models/saved_wrapped_period.dart';
import '../../services/app_translations.dart';
import '../../services/keepsake_pdf_service.dart';
import '../../services/locale_service.dart';
import '../../services/premium_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/premium_upsell_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../profile/wrapped_screen.dart' show PeriodPickerSheet, WrappedScreen;
import 'premium_screen.dart';
import 'saved_periods_screen.dart';
import '../../theme/notebook_paper.dart';
import '../../theme/clay_kit.dart';

/// "Keepsake export" — turns logged history into a soft, paper-styled
/// PDF (see services/keepsake_pdf_service.dart) that can be saved,
/// printed, or sent via the OS share sheet. Premium-only, reached from
/// Settings' premium section, the diary/Wrapped screens' own header
/// icons, or (see [lockedWrappedSummary]) straight out of a Wrapped
/// carousel that's already on screen.
///
/// Two tabs, top of the sheet:
///  - **diary** — the whole logged history, oldest first.
///  - **wrapped** — one period's [WrappedSummary] (same picker as
///    [PeriodPickerSheet] on the Wrapped screen itself) turned into a
///    run of full-bleed story pages plus a receipt.
///
/// Not-premium visitors see a locked preview with a straight line to
/// [PremiumScreen] rather than the export controls — same "show what
/// it's for, then invite" shape as the rest of the paywall surfaces,
/// just scoped to one feature instead of the whole plan.
class KeepsakeExportScreen extends StatefulWidget {
  // Set only when arriving from a Wrapped carousel that's already
  // showing a real summary (see WrappedScreen's _WrappedCarouselState.
  // _openKeepsake) — including a custom-range one from
  // CustomWrappedService, which has no backend endpoint to re-fetch
  // from. When set, the Wrapped tab exports exactly this summary
  // instead of fetching by scope/year/month, and its own period picker
  // is replaced with a static label since there's nothing to re-pick.
  final WrappedSummary? lockedWrappedSummary;
  const KeepsakeExportScreen({super.key, this.lockedWrappedSummary});

  @override
  State<KeepsakeExportScreen> createState() => _KeepsakeExportScreenState();
}

enum _ExportKind { diary, wrapped }

class _KeepsakeExportScreenState extends State<KeepsakeExportScreen> {
  bool _busy = false;
  String? _error;
  late _ExportKind _kind;

  // Wrapped period state — mirrors WrappedScreen's own defaults (this
  // year) so opening the tab for the first time shows something real
  // rather than an empty picker. Unused whenever a locked summary was
  // handed in instead (see widget.lockedWrappedSummary).
  String _scope = 'year';
  int? _year;
  int? _month;
  WrappedSummary? _wrappedPreview;
  bool _loadingPreview = false;
  Future<WrappedPeriods>? _periodsFuture;

  bool get _locked => widget.lockedWrappedSummary != null;

  @override
  void initState() {
    super.initState();
    if (_locked) {
      _wrappedPreview = widget.lockedWrappedSummary;
      _kind = _ExportKind.wrapped;
    } else {
      _kind = _ExportKind.diary;
      _loadWrappedPreview();
    }
  }

  Future<void> _loadWrappedPreview() async {
    setState(() => _loadingPreview = true);
    try {
      final summary = await context
          .read<AppState>()
          .profile
          .wrappedSummary(scope: _scope, year: _year, month: _month);
      if (!mounted) return;
      setState(() {
        _wrappedPreview = summary;
        _loadingPreview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPreview = false);
    }
  }

  Future<void> _openPeriodPicker() async {
    if (_locked) return; // nothing to re-pick — see widget.lockedWrappedSummary
    _periodsFuture ??= context.read<AppState>().profile.wrappedPeriods();
    final periods = await _periodsFuture!;
    if (!mounted) return;
    final isPremium = context.read<PremiumService>().isPremium;
    await showModalBottomSheet(
      context: context,
      backgroundColor: SeenlyPalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PeriodPickerSheet(
        periods: periods,
        currentScope: _scope,
        currentYear: _year,
        currentMonth: _month,
        isPremium: isPremium,
        onSelect: (scope, year, month) {
          Navigator.of(context).pop();
          setState(() {
            _scope = scope;
            _year = year;
            _month = month;
          });
          _loadWrappedPreview();
        },
        onCustom: () async {
          Navigator.of(context).pop();
          if (!isPremium) {
            showPremiumUpsellSheet(
              context,
              triggerSource: 'custom_wrapped',
              icon: Icons.calendar_month_outlined,
              title: 'свой итог — премиум-функция'.tr,
              message: 'назови любой период — поездку, сезон, отношения — и получи полноценный итог по нему'.tr,
            );
            return;
          }
          // A custom range only ever exists as a live WrappedScreen
          // summary (see CustomWrappedService) — SavedPeriodsScreen
          // just picks a saved (or freshly-made) period; opening that
          // carousel is on us here. Its own export icon (see
          // WrappedScreen's _openKeepsake) is the way back into a PDF
          // of it, with this screen left on the stack behind it.
          final period = await Navigator.of(context)
              .push<SavedWrappedPeriod>(MaterialPageRoute(builder: (_) => const SavedPeriodsScreen()));
          if (period == null || !context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WrappedScreen(
              initialScope: 'custom',
              customTitle: period.title,
              customRange: period.range,
            ),
          ));
        },
      ),
    );
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final app = context.read<AppState>();
      final user = app.currentUser;
      final name = (user?.displayName?.isNotEmpty ?? false) ? user!.displayName! : (user?.username ?? '');

      final Uint8List bytes;
      final String filename;
      if (_kind == _ExportKind.diary) {
        final entries = await app.diary.list();
        bytes = await KeepsakePdfService.build(entries: entries, personName: name);
        filename = 'tanè-diary.pdf';
      } else {
        final summary = _wrappedPreview ??
            await app.profile.wrappedSummary(scope: _scope, year: _year, month: _month);
        bytes = await KeepsakePdfService.buildWrapped(summary: summary, personName: name);
        filename = 'tanè-wrapped.pdf';
      }
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = (_kind == _ExportKind.diary
              ? 'couldn\'t put the keepsake together — try again'
              : 'couldn\'t put your wrapped together — try again')
          .tr);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
              child: _KindSwitch(
                kind: _kind,
                onChanged: (k) => setState(() {
                  _kind = k;
                  _error = null;
                }),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_kind == _ExportKind.diary) ...[
                      const _DiaryPreview(),
                      const SizedBox(height: 24),
                      Text('what goes in it'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                      const SizedBox(height: 10),
                      _DiaryInfoCard(isPremium: isPremium),
                    ] else ...[
                      _WrappedPreview(
                        summary: _wrappedPreview,
                        loading: _loadingPreview,
                        locked: _locked,
                        onPickPeriod: _openPeriodPicker,
                      ),
                      const SizedBox(height: 24),
                      Text('what goes in it'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                      const SizedBox(height: 10),
                      _WrappedInfoCard(isPremium: isPremium),
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
                    onTap: isPremium
                        ? _export
                        : () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
                    scaleTo: 0.97,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.accent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      alignment: Alignment.center,
                      child: _busy
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
                                Icon(
                                  isPremium ? Icons.ios_share : Icons.lock_outline,
                                  size: 15,
                                  color: SeenlyPalette.accentOnAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isPremium
                                      ? (_kind == _ExportKind.diary ? 'make my keepsake'.tr : 'make my wrapped'.tr)
                                      : 'unlock with premium'.tr,
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

/// The diary/wrapped segmented switch at the top of the sheet — two
/// equal-width pill buttons sharing one pill-shaped track, same visual
/// language as the app's other segmented pickers (filters, decide
/// method).
class _KindSwitch extends StatelessWidget {
  final _ExportKind kind;
  final ValueChanged<_ExportKind> onChanged;
  const _KindSwitch({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SeenlyPalette.cork,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, _ExportKind.diary, 'diary'.tr, Icons.auto_stories_outlined)),
          Expanded(child: _segment(context, _ExportKind.wrapped, 'wrapped'.tr, Icons.auto_awesome_outlined)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _ExportKind value, String label, IconData icon) {
    final active = value == kind;
    return PressScale(
      onTap: () => onChanged(value),
      scaleTo: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: ClayBoxDecoration(
          color: active ? SeenlyPalette.paper : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active ? SeenlyPalette.softShadow : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? SeenlyPalette.accent : SeenlyPalette.inkFaint),
            const SizedBox(width: 6),
            Text(label,
                style: SeenlyText.serif(
                    size: 13,
                    weight: FontWeight.w600,
                    color: active ? SeenlyPalette.ink : SeenlyPalette.inkFaint)),
          ],
        ),
      ),
    );
  }
}

/// A small, static mockup of the diary PDF's cover — not the real
/// document (that's only ever built on export), just enough of a
/// preview to show what the keepsake looks like before committing to
/// generating one.
class _DiaryPreview extends StatelessWidget {
  const _DiaryPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.accent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SeenlyPalette.mustard, width: 1.4),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.mustard),
            ),
          ),
          const SizedBox(height: 14),
          Text('your diary'.tr,
              style: SeenlyText.serif(italic: true, size: 20, color: SeenlyPalette.accentOnAccent)),
          const SizedBox(height: 6),
          Text('a keepsake to print, save, or send'.tr,
              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accentOnAccent.withOpacity(0.85))),
        ],
      ),
    );
  }
}

/// Same idea as [_DiaryPreview], for the Wrapped tab — shows the
/// currently-picked period's real headline number once it's loaded, so
/// choosing a period feels connected to what's about to be exported
/// rather than just a filter sitting above an unrelated mockup.
class _WrappedPreview extends StatelessWidget {
  final WrappedSummary? summary;
  final bool loading;
  final bool locked;
  final VoidCallback onPickPeriod;
  const _WrappedPreview(
      {required this.summary, required this.loading, required this.locked, required this.onPickPeriod});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.accent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('W R A P P E D',
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.accentOnAccent.withOpacity(0.8))),
          const SizedBox(height: 10),
          if (loading)
            SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(SeenlyPalette.accentOnAccent),
                  ),
                ),
              ),
            )
          else if (s == null || s.totalLogged == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                LocaleService.appIsRussian
                    ? 'за этот период в дневнике пока пусто'
                    : 'the diary is still empty for this period',
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
              ),
            )
          else ...[
            Text('${s.totalLogged}',
                style: SeenlyText.serif(size: 44, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent)),
            const SizedBox(height: 2),
            Text(
              LocaleService.appIsRussian ? 'вечеров записано' : 'evenings logged',
              style: SeenlyText.mono(size: 10, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
            ),
          ],
          const SizedBox(height: 14),
          if (locked)
            // Nothing to re-pick — this exact summary is what gets
            // exported (see KeepsakeExportScreen.lockedWrappedSummary).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: SeenlyPalette.accentOnAccent.withOpacity(0.12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 12, color: SeenlyPalette.accentOnAccent),
                  const SizedBox(width: 6),
                  Text(
                    s?.periodLabel ?? '',
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else
            PressScale(
              onTap: onPickPeriod,
              scaleTo: 0.97,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SeenlyPalette.accentOnAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: SeenlyPalette.accentOnAccent),
                    const SizedBox(width: 6),
                    Text(
                      s?.periodLabel ?? 'choose a period'.tr,
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.accentOnAccent, weight: FontWeight.w600),
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

class _DiaryInfoCard extends StatelessWidget {
  final bool isPremium;
  const _DiaryInfoCard({required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return _InfoShell(rows: [
      _InfoRow(
        icon: Icons.auto_stories_outlined,
        title: 'every logged evening'.tr,
        subtitle: 'grouped month by month, oldest first, with real posters'.tr,
      ),
      _InfoRow(
        icon: Icons.palette_outlined,
        title: 'the same soft, paper look'.tr,
        subtitle: 'no watermark, no upgrade nag on the page'.tr,
      ),
      _InfoRow(
        icon: Icons.ios_share,
        title: 'yours to keep'.tr,
        subtitle: isPremium
            ? 'save it, print it, or send it — your choice'.tr
            : 'included with premium'.tr,
      ),
    ]);
  }
}

class _WrappedInfoCard extends StatelessWidget {
  final bool isPremium;
  const _WrappedInfoCard({required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return _InfoShell(rows: [
      _InfoRow(
        icon: Icons.calendar_month_outlined,
        title: 'any period you\'ve logged in'.tr,
        subtitle: 'this month, this year, all time, or any earlier one'.tr,
      ),
      _InfoRow(
        icon: Icons.auto_awesome_outlined,
        title: 'the full wrapped story'.tr,
        subtitle: 'totals, genres, rhythm, your archetype, top reviews'.tr,
      ),
      _InfoRow(
        icon: Icons.receipt_long_outlined,
        title: 'a keepsake receipt at the end'.tr,
        subtitle: isPremium
            ? 'save it, print it, or send it — your choice'.tr
            : 'included with premium'.tr,
      ),
    ]);
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
            if (i != rows.length - 1) const _InfoDivider(),
          ],
        ],
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: CozyDivider(height: 1, color: SeenlyPalette.border),
      );
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
