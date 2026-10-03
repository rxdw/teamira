import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../utils/album_dates.dart';
import '../../../widgets/wow_motion.dart';
import 'album_paywall.dart';
import 'album_strings.dart';
import 'album_widgets.dart';
import 'note_compose_sheet.dart' show SoftSizeSwitch;

/// Opens the sheet for sealing a new capsule — a date and my own letter, in
/// one go. A free circle can seal one; once it has, it gets the paywall
/// instead (see [AlbumStatus.canCreateCapsule]).
///
/// Returns the capsule the server created, or null if dismissed.
Future<Capsule?> showCapsuleComposeSheet(
  BuildContext context, {
  required AlbumStatus status,
  required String partnerName,
}) async {
  if (!status.canCreateCapsule) {
    await showAlbumPaywall(
      context,
      kind: AlbumPaywallKind.capsule,
      source: 'pair_album_capsule_limit',
    );
    return null;
  }
  return showAlbumSheet<Capsule>(
    context,
    builder: (_) => _CapsuleComposer(status: status, partnerName: partnerName),
  );
}

/// Opens the sheet for adding *my* letter to a capsule the partner sealed.
/// Never gated: the capsule already exists, and the other half of a promise
/// for two can't sit behind a plan.
Future<Capsule?> showCapsuleLetterSheet(
  BuildContext context, {
  required AlbumStatus status,
  required Capsule capsule,
  required String partnerName,
}) async {
  return showAlbumSheet<Capsule>(
    context,
    builder: (_) => _CapsuleComposer(status: status, partnerName: partnerName, addTo: capsule),
  );
}

class _Preset {
  final String ru;
  final String en;
  final int months;
  const _Preset(this.ru, this.en, this.months);
}

const List<_Preset> _presets = [
  _Preset('3 месяца', '3 months', 3),
  _Preset('полгода', '6 months', 6),
  _Preset('год', 'a year', 12),
  _Preset('2 года', '2 years', 24),
];

class _CapsuleComposer extends StatefulWidget {
  final AlbumStatus status;
  final String partnerName;
  final Capsule? addTo;
  const _CapsuleComposer({required this.status, required this.partnerName, this.addTo});

  @override
  State<_CapsuleComposer> createState() => _CapsuleComposerState();
}

class _CapsuleComposerState extends State<_CapsuleComposer> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  // Default: "a year" — the feature's own name.
  int? _presetMonths = 12;
  DateTime? _customDate;
  bool _saving = false;
  bool _sealed = false;
  String? _error;
  Capsule? _result;

  bool get _adding => widget.addTo != null;
  DateTime get _today => widget.status.serverToday;

  /// Same day N months on, clamped to the last day of a shorter month so
  /// "31 jan + 1 month" never spills into March.
  DateTime _plusMonths(int months) {
    final t = _today;
    final total = t.month - 1 + months;
    final year = t.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, t.day > lastDay ? lastDay : t.day);
  }

  DateTime get _opensOn {
    if (_adding) return widget.addTo!.opensOn;
    if (_customDate != null) return _customDate!;
    return _plusMonths(_presetMonths ?? 12);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSave {
    final n = _body.text.trim().length;
    return !_saving && n > 0 && n <= kAlbumLetterMaxChars;
  }

  Future<void> _pickDate() async {
    // Calendar days, not 24-hour Durations (see nextDayMilestone).
    final first = DateTime(_today.year, _today.month, _today.day + kAlbumCapsuleMinDays);
    final last = DateTime(_today.year, _today.month, _today.day + kAlbumCapsuleMaxDays);
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? _plusMonths(12),
      firstDate: first,
      lastDate: last,
      helpText: at('когда откроем?', 'when do we open it?'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDate = DateTime(picked.year, picked.month, picked.day);
      _presetMonths = null;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = _body.text.trim();
      final Capsule capsule = _adding
          ? await _service.addLetter(widget.addTo!.id, body)
          : await _service.createCapsule(opensOn: _opensOn, body: body, title: _title.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _result = capsule;
      setState(() {
        _saving = false;
        _sealed = true;
      });
      final wait = albumReduceMotion(context) ? 600 : 1900;
      Future.delayed(Duration(milliseconds: wait), () {
        if (mounted) Navigator.of(context).pop(_result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (PairAlbumService.isPaywall(e)) {
        await showAlbumPaywall(
          context,
          kind: AlbumPaywallKind.capsule,
          source: 'pair_album_capsule_limit',
        );
        return;
      }
      setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftSizeSwitch(child: _sealed ? _sealedView(context) : _formView(context));
  }

  Widget _sealedView(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final still = albumReduceMotion(context);
    return Padding(
      key: const ValueKey('sealed'),
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: still ? 0.0 : 1.0, end: 0.0),
            duration: still ? Duration.zero : const Duration(milliseconds: 1100),
            curve: Curves.easeInOutCubic,
            builder: (_, v, __) => EnvelopeView(
              progress: v,
              width: 240,
              sealColor: SeenlyPalette.accent,
              letter: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: NotePaper(
                    body: _body.text.trim(),
                    fontSize: 11,
                    tint: SeenlyPalette.periwinkle,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Entrance(
            delay: const Duration(milliseconds: 600),
            riseBy: 10,
            child: Text(
              _adding ? at('письмо запечатано', 'letter sealed') : at('капсула запечатана', 'capsule sealed'),
              style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Entrance(
            delay: const Duration(milliseconds: 780),
            riseBy: 8,
            child: Text(
              at(
                'откроется ${albumDateLabel(_opensOn, ru: ru)}',
                'opens ${albumDateLabel(_opensOn, ru: ru)}',
              ),
              style: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formView(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final count = _body.text.trim().length;
    final over = count > kAlbumLetterMaxChars;
    final days = albumDaysBetween(_today, _opensOn);
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _adding
                ? at('ваше письмо в капсулу', 'your letter for the capsule')
                : at('капсула для двоих', 'a capsule for two'),
            style: SeenlyText.serif(size: 20, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _adding
                ? at(
                    '${widget.partnerName} уже запечатал(а) своё письмо. добавьте своё — '
                        'откроете вместе ${albumDateLabel(_opensOn, ru: ru)}',
                    '${widget.partnerName} already sealed a letter. add yours — you\'ll open '
                        'it together on ${albumDateLabel(_opensOn, ru: ru)}',
                  )
                : at(
                    'напишите письмо себе-будущим. ${widget.partnerName} получит уведомление и '
                        'сможет добавить своё. открыть капсулу можно будет только вместе — в назначенный день',
                    'write a letter to your future selves. ${widget.partnerName} gets a nudge '
                        'and can add theirs. it only opens on the day you choose',
                  ),
            style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
          ),
          if (!_adding) ...[
            const SizedBox(height: 16),
            Text(at('когда откроем', 'when it opens'),
                style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _presets)
                  _DateChip(
                    label: ru ? p.ru : p.en,
                    selected: _presetMonths == p.months && _customDate == null,
                    onTap: () => setState(() {
                      _presetMonths = p.months;
                      _customDate = null;
                    }),
                  ),
                _DateChip(
                  label: _customDate != null
                      ? albumDateLabel(_customDate!, ru: ru)
                      : at('своя дата', 'pick a date'),
                  icon: Icons.event_rounded,
                  selected: _customDate != null,
                  onTap: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.lock_clock_rounded, size: 16, color: SeenlyPalette.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    at(
                      '${albumDateLabel(_opensOn, ru: ru)} · ${countdownLabel(days)}',
                      '${albumDateLabel(_opensOn, ru: ru)} · ${countdownLabel(days)}',
                    ),
                    style: SeenlyText.mono(size: 12, weight: FontWeight.w600, color: SeenlyPalette.accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: kAlbumCapsuleTitleMaxChars,
              textCapitalization: TextCapitalization.sentences,
              style: SeenlyText.serif(size: 15.5, weight: FontWeight.w500),
              cursorColor: SeenlyPalette.accent,
              decoration: InputDecoration(
                counterText: '',
                hintText: at('название (необязательно): «через год»', 'title (optional): "a year from now"'),
                hintStyle: SeenlyText.mono(size: 12.5, color: SeenlyPalette.inkFaint),
                filled: true,
                fillColor: SeenlyPalette.ink.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            decoration: BoxDecoration(
              color: Color.lerp(SeenlyPalette.paper, SeenlyPalette.periwinkle, 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: over ? SeenlyPalette.coral : SeenlyPalette.periwinkle.withOpacity(0.4),
              ),
            ),
            child: TextField(
              controller: _body,
              minLines: 6,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              style: SeenlyText.handwrittenNote(size: 18, color: SeenlyPalette.ink).copyWith(height: 1.4),
              cursorColor: SeenlyPalette.accent,
              decoration: InputDecoration.collapsed(
                hintText: at(
                  'что вам сейчас важно? о чём мечтаете? что хотите не забыть?',
                  'what matters to you right now? what are you dreaming about?',
                ),
                hintStyle: SeenlyText.handwrittenNote(size: 17, color: SeenlyPalette.inkFaint),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$count/$kAlbumLetterMaxChars',
                style: SeenlyText.mono(size: 11, color: over ? SeenlyPalette.coral : SeenlyPalette.inkFaint),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: SeenlyPalette.mustard.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: SeenlyPalette.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _adding
                        ? at(
                            'после запечатывания письмо нельзя изменить, и прочитать его не сможет никто — даже вы — до дня открытия',
                            'once sealed a letter can\'t be changed, and nobody — you included — can read it until the day',
                          )
                        : at(
                            'дату потом изменить нельзя — в этом и обещание. письмо никто не прочтёт до этого дня, даже вы',
                            'the date can\'t be changed later — that\'s the promise. nobody reads the letter before then, you included',
                          ),
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          // The free capsule is a gift worth naming — said once, where the
          // person is about to use it, and only to a circle without a plan.
          if (!_adding && !widget.status.isPremium && widget.status.capsulesLeft == 1) ...[
            const SizedBox(height: 10),
            FreeAllowanceNote(
              text: at(
                'эта капсула — бесплатная. следующие — с подпиской на двоих',
                'this capsule is on us. the next ones come with a plan for two',
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.coral)),
          ],
          const SizedBox(height: 18),
          ClayButton(
            label: _adding ? at('запечатать письмо', 'seal my letter') : at('запечатать капсулу', 'seal the capsule'),
            icon: Icons.lock_outline_rounded,
            loading: _saving,
            onTap: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _DateChip({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.ink.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: SeenlyText.mono(
                size: 12.5,
                weight: FontWeight.w600,
                color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
