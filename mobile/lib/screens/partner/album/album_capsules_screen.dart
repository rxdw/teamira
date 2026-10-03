import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../utils/album_dates.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/themed_loading_indicator.dart';
import '../../../widgets/themed_pull_to_refresh.dart';
import '../../../widgets/wow_motion.dart';
import 'album_strings.dart';
import 'album_widgets.dart';
import 'capsule_compose_sheet.dart';
import 'capsule_open_screen.dart';

/// Every capsule the pair has: the ones still sealed (with a countdown and
/// a ring that fills toward the day), the ones that have just become
/// openable (a glowing invitation), and the opened archive.
///
/// The countdown is drawn from the server's day, never the phone's clock.
class AlbumCapsulesScreen extends StatefulWidget {
  final AlbumStatus status;
  const AlbumCapsulesScreen({super.key, required this.status});

  @override
  State<AlbumCapsulesScreen> createState() => _AlbumCapsulesScreenState();
}

class _AlbumCapsulesScreenState extends State<AlbumCapsulesScreen> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);

  late AlbumStatus _status = widget.status;
  List<Capsule> _capsules = const [];
  bool _loading = true;
  String? _error;

  String get _partnerName => _status.partner?.name ?? at('партнёр', 'partner');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([_service.status(), _service.capsules()]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as AlbumStatus;
        _capsules = results[1] as List<Capsule>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e);
      });
    }
  }

  Future<void> _create() async {
    final made = await showCapsuleComposeSheet(context, status: _status, partnerName: _partnerName);
    if (made != null && mounted) await _load(silent: true);
  }

  Future<void> _addLetter(Capsule c) async {
    final updated = await showCapsuleLetterSheet(
      context,
      status: _status,
      capsule: c,
      partnerName: _partnerName,
    );
    if (updated != null && mounted) await _load(silent: true);
  }

  Future<void> _open(Capsule c) async {
    await showCapsuleOpening(
      context,
      capsule: c,
      partnerName: _partnerName,
      serverToday: _status.serverToday,
    );
    if (mounted) await _load(silent: true);
  }

  Future<void> _delete(Capsule c) async {
    final ok = await showAlbumSheet<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(at('убрать капсулу?', 'remove this capsule?'),
                style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              at(
                'ваше письмо в ней пропадёт насовсем. пока партнёр не добавил своё, капсулу ещё можно убрать',
                'your letter in it will be gone for good. while your partner hasn\'t added theirs you can still take it back',
              ),
              style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 18),
            ClayButton(
              label: at('убрать', 'remove'),
              color: SeenlyPalette.coral,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(at('оставить', 'keep it'),
                    style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteCapsule(c.id);
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _capsules.where((c) => c.ready).toList();
    final sealed = _capsules.where((c) => !c.isOpen).toList();
    final opened = _capsules.where((c) => c.isOpen && c.openedByMe).toList();

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: ThemedPullToRefresh(
          onRefresh: () => _load(silent: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: ThemedLoadingIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: SeenlyText.emptyState()),
                          const SizedBox(height: 16),
                          ClayButton(label: at('повторить', 'retry'), expand: false, onTap: _load),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                if (_capsules.isEmpty) SliverToBoxAdapter(child: _empty()),
                if (ready.isNotEmpty) ..._section(at('можно открывать', 'ready to open'), ready),
                if (sealed.isNotEmpty) ..._section(at('запечатаны', 'sealed'), sealed),
                if (opened.isNotEmpty) ..._section(at('открытые', 'opened'), opened),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.ink),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Entrance(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(at('капсулы времени', 'time capsules'), style: SeenlyText.screenTitle),
                  const SizedBox(height: 4),
                  Text(
                    at(
                      'письма себе-будущим: запечатали сегодня — откроете вместе в назначенный день',
                      'letters to your future selves: sealed today, opened together on the day',
                    ),
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  ClayButton(
                    label: at('запечатать новую капсулу', 'seal a new capsule'),
                    icon: Icons.add_rounded,
                    expand: false,
                    onTap: _create,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 0),
      child: Entrance(
        delay: const Duration(milliseconds: 150),
        child: Column(
          children: [
            BreathingGlow(
              color: SeenlyPalette.periwinkle,
              size: 260,
              child: const _CapsuleRing(progress: 0.0, size: 130, daysLabel: '∞'),
            ),
            const SizedBox(height: 16),
            Text(
              at('пока ни одной капсулы', 'no capsules yet'),
              style: SeenlyText.serif(size: 17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              at(
                'напишите друг другу письма, запечатайте их — и встретьтесь с собой через год',
                'write each other letters, seal them — and meet yourselves a year from now',
              ),
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String title, List<Capsule> items) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: SectionHeader(title: title),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final c = items[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Entrance(
                key: ValueKey('capsule-${c.id}'),
                delay: Duration(milliseconds: 60 * (i % 5)),
                riseBy: 16,
                child: _CapsuleCard(
                  capsule: c,
                  status: _status,
                  partnerName: _partnerName,
                  onOpen: () => _open(c),
                  onAddLetter: () => _addLetter(c),
                  onDelete: () => _delete(c),
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    ];
  }
}

/// A ring that fills as the capsule's day approaches, with the days left in
/// the middle. `progress` is 0 → 1 across the whole sealed period.
class _CapsuleRing extends StatelessWidget {
  final double progress;
  final double size;
  final String daysLabel;
  final Color? color;
  const _CapsuleRing({required this.progress, required this.size, required this.daysLabel, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? SeenlyPalette.accent;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
            duration: albumReduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(v, c, SeenlyPalette.ink.withOpacity(0.08)),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: size * 0.2, color: c),
              SizedBox(height: size * 0.03),
              Text(
                daysLabel,
                style: SeenlyText.serif(size: size * 0.2, weight: FontWeight.w700, color: SeenlyPalette.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter(this.progress, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

class _CapsuleCard extends StatelessWidget {
  final Capsule capsule;
  final AlbumStatus status;
  final String partnerName;
  final VoidCallback onOpen;
  final VoidCallback onAddLetter;
  final VoidCallback onDelete;
  const _CapsuleCard({
    required this.capsule,
    required this.status,
    required this.partnerName,
    required this.onOpen,
    required this.onAddLetter,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final title = (capsule.title != null && capsule.title!.trim().isNotEmpty)
        ? capsule.title!
        : at('капсула времени', 'time capsule');

    // Progress across the sealed period, by server days.
    final created = DateTime(capsule.createdAt.toLocal().year, capsule.createdAt.toLocal().month,
        capsule.createdAt.toLocal().day);
    final total = math.max(1, albumDaysBetween(created, capsule.opensOn));
    final done = albumDaysBetween(created, status.serverToday);
    final progress = capsule.isOpen ? 1.0 : (done / total);

    if (capsule.ready) {
      return PressScale(
        onTap: onOpen,
        haptics: true,
        scaleTo: 0.98,
        child: BreathingGlow(
          color: SeenlyPalette.mustard,
          size: 40,
          maxOpacity: 0.35,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: ClayBoxDecoration(
              boxShadow: SeenlyPalette.flatCardShadow,
              color: SeenlyPalette.accent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const WaxSeal(size: 52, color: Color(0xFFE9B949)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        at('пора открывать', 'time to open it'),
                        style: SeenlyText.serif(size: 18, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeenlyText.mono(size: 12, color: SeenlyPalette.accentOnAccent.withOpacity(0.85)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: SeenlyPalette.accentOnAccent),
              ],
            ),
          ),
        ),
      );
    }

    if (capsule.isOpen) {
      // Opened archive: tap to read the letters again.
      return PressScale(
        onTap: onOpen,
        scaleTo: 0.98,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.border),
          ),
          child: Row(
            children: [
              Icon(Icons.drafts_outlined, color: SeenlyPalette.sage, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      at('открыта ${albumDateLabel(capsule.opensOn, ru: ru)}',
                          'opened ${albumDateLabel(capsule.opensOn, ru: ru)}'),
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
      );
    }

    // Sealed.
    final needsMyLetter = !capsule.myLetterSealed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SeenlyPalette.border),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CapsuleRing(
                progress: progress,
                size: 86,
                daysLabel: capsule.daysLeft >= 100 ? '${capsule.daysLeft}' : '${capsule.daysLeft}',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                      at('откроется ${albumDateLabel(capsule.opensOn, ru: ru)}',
                          'opens ${albumDateLabel(capsule.opensOn, ru: ru)}'),
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countdownLabel(capsule.daysLeft),
                      style: SeenlyText.mono(size: 11.5, weight: FontWeight.w600, color: SeenlyPalette.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LetterDot(
                filled: capsule.myLetterSealed,
                label: at('ваше письмо', 'your letter'),
              ),
              const SizedBox(width: 14),
              _LetterDot(
                filled: capsule.partnerLetterSealed,
                label: at('письмо от $partnerName', 'letter from $partnerName'),
              ),
            ],
          ),
          if (needsMyLetter) ...[
            const SizedBox(height: 14),
            ClayButton(
              label: at('добавить своё письмо', 'add my letter'),
              icon: Icons.edit_note_rounded,
              onTap: onAddLetter,
            ),
          ],
          if (capsule.canDelete)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDelete,
                child: Text(
                  at('убрать капсулу', 'remove capsule'),
                  style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LetterDot extends StatelessWidget {
  final bool filled;
  final String label;
  const _LetterDot({required this.filled, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = filled ? SeenlyPalette.sage : SeenlyPalette.inkFaint;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(filled ? Icons.mark_email_read_rounded : Icons.mail_outline_rounded, size: 16, color: c),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.mono(size: 11, color: filled ? SeenlyPalette.inkMuted : SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
