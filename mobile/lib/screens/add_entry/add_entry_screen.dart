import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../services/log_theme_service.dart';
import '../../widgets/heart_rating.dart';
import '../../widgets/log_ritual.dart';
import '../../widgets/mood_tag_picker.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart' show Entrance, FadeInNetworkImage, PressScale;
import '../../services/app_translations.dart';

enum _WhenChoice { today, yesterday, custom }

class AddEntryScreen extends StatefulWidget {
  final MediaItem item;
  const AddEntryScreen({super.key, required this.item});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  _WhenChoice _when = _WhenChoice.today;
  DateTime? _customDate;
  int _rating = 0;
  final _noteController = TextEditingController();
  List<String> _moodTags = [];
  bool _saving = false;

  // Only shown once we know there's actually a partner linked — a failed
  // or "not linked" status just quietly keeps this toggle hidden rather
  // than showing an error on a screen that isn't primarily about it.
  String? _partnerUsername;
  bool _watchedWithPartner = false;

  @override
  void initState() {
    super.initState();
    _loadPartnerStatus();
  }

  Future<void> _loadPartnerStatus() async {
    try {
      final status = await context.read<AppState>().partner.status();
      if (!mounted) return;
      if (status.linked) {
        setState(() => _partnerUsername = status.partnerUsername);
      }
    } catch (_) {
      // Best-effort — just stays hidden.
    }
  }

  DateTime get _resolvedDate {
    switch (_when) {
      case _WhenChoice.today:
        return DateTime.now();
      case _WhenChoice.yesterday:
        return DateTime.now().subtract(const Duration(days: 1));
      case _WhenChoice.custom:
        return _customDate ?? DateTime.now();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _when = _WhenChoice.custom;
        _customDate = picked;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().diary.logEntry(
            item: widget.item,
            rating: _rating > 0 ? _rating : null,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            moodTags: _moodTags.isEmpty ? null : _moodTags,
            watchedAt: _resolvedDate,
            watchedWithPartner: _watchedWithPartner,
          );
      if (mounted) {
        // The seat/page-picking and the ticket/stamp itself are the
        // confirmation — no snackbar needed on top of either. Which one
        // plays is whatever's set in Settings; picking first is pure
        // ritual (any choice "works"), then the mark itself lands, then
        // we close out.
        await showPreLogRitual(
          context,
          title: widget.item.title.display,
          mediaType: widget.item.mediaType,
          runtimeMinutes: widget.item.runtimeMinutes,
        );
        if (mounted) {
          await showLogDrop(
            context,
            title: widget.item.title.display,
            mediaType: widget.item.mediaType,
            rating: _rating > 0 ? _rating : null,
            watchedAt: _resolvedDate,
            runtimeMinutes: widget.item.runtimeMinutes,
          );
        }
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('couldn\'t save that just now — try again'.tr)),
        );
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text('cancel'.tr,
                        style: SeenlyText.mono(size: 13, color: SeenlyPalette.inkMuted)),
                  ),
                  Text('new entry'.tr, style: SeenlyText.cardTitle),
                  PressScale(
                    onTap: _saving ? null : _save,
                    haptics: true,
                    child: Text('save'.tr,
                        style: SeenlyText.mono(size: 13, color: SeenlyPalette.accent)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
                children: [
                  Entrance(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: SizedBox(
                              width: 52,
                              height: 74,
                              child: item.posterUrl != null
                                  ? FadeInNetworkImage(
                                      url: item.posterUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                                    )
                                  : Container(color: SeenlyPalette.mediaColor(item.mediaType)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title.display, style: SeenlyText.cardTitle),
                                const SizedBox(height: 3),
                                Text('${mediaTypeLabel(item.mediaType)} · ${item.year ?? '—'}',
                                    style: SeenlyText.metaLabel),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 60),
                    child: Text('when'.tr, style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                  ),
                  const SizedBox(height: 10),
                  Entrance(
                    delay: const Duration(milliseconds: 90),
                    riseBy: 12,
                    child: Row(
                      children: [
                        PillChip(
                          label: 'today'.tr,
                          active: _when == _WhenChoice.today,
                          onTap: () => setState(() => _when = _WhenChoice.today),
                        ),
                        const SizedBox(width: 8),
                        PillChip(
                          label: 'yesterday'.tr,
                          active: _when == _WhenChoice.yesterday,
                          onTap: () => setState(() => _when = _WhenChoice.yesterday),
                        ),
                        const SizedBox(width: 8),
                        PillChip(
                          label: _when == _WhenChoice.custom && _customDate != null
                              ? '${_customDate!.month}/${_customDate!.day}'
                              : 'pick date',
                          active: _when == _WhenChoice.custom,
                          onTap: _pickDate,
                        ),
                      ],
                    ),
                  ),
                  if (_partnerUsername != null) ...[
                    const SizedBox(height: 22),
                    Entrance(
                      delay: const Duration(milliseconds: 120),
                      child: Text('together'.tr,
                          style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                    ),
                    const SizedBox(height: 10),
                    Entrance(
                      delay: const Duration(milliseconds: 150),
                      riseBy: 12,
                      child: PillChip(
                        label: "${'watched with'.tr} $_partnerUsername",
                        active: _watchedWithPartner,
                        onTap: () => setState(() => _watchedWithPartner = !_watchedWithPartner),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 140),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('how it felt'.tr,
                            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _rating > 0
                              ? Text('$_rating/10',
                                  key: ValueKey(_rating),
                                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.ratingColor(_rating)))
                              : const SizedBox.shrink(key: ValueKey('none')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Entrance(
                    delay: const Duration(milliseconds: 170),
                    riseBy: 12,
                    child: HeartRating(
                      value: _rating,
                      max: 10,
                      size: 22,
                      onChanged: (v) => setState(() => _rating = v == _rating ? 0 : v),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 200),
                    child: Text(vibePromptTitle(_rating), style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                  ),
                  const SizedBox(height: 10),
                  Entrance(
                    delay: const Duration(milliseconds: 230),
                    riseBy: 12,
                    child: MoodTagPicker(
                      selected: _moodTags,
                      onChanged: (tags) => setState(() => _moodTags = tags),
                      rating: _rating,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    delay: const Duration(milliseconds: 260),
                    child: Text('a note to your future self'.tr,
                        style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.accent)),
                  ),
                  const SizedBox(height: 10),
                  Entrance(
                    delay: const Duration(milliseconds: 290),
                    riseBy: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: TextField(
                        controller: _noteController,
                        minLines: 3,
                        maxLines: 6,
                        style: SeenlyText.bodyText,
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          hintText: 'watched it with... felt like...'.tr,
                          hintStyle:
                              SeenlyText.serif(color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: LogSubmitButton(
                label: switch (context.watch<LogThemeService>().theme) {
                  LogTheme.coach => 'tear off tonight\'s pass',
                  LogTheme.ticket => 'tuck tonight\'s ticket away',
                  LogTheme.garden => 'plant tonight in the bed',
                },
                loading: _saving,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
