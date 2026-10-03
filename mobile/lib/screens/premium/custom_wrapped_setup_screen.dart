import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/saved_wrapped_period.dart';
import '../../services/app_translations.dart';
import '../../services/custom_wrapped_service.dart';
import '../../services/saved_periods_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import '../../theme/clay_kit.dart';

/// The "name a new period" step for "свой период" — a title and a date
/// range, saved (see SavedPeriodsService) and handed straight back to
/// whoever opened this screen as a [SavedWrappedPeriod] (or `null` if
/// they back out) via `Navigator.pop`. [SavedPeriodsScreen] is the
/// actual "свой период" landing page this hangs off of, reached from
/// its own "+" — the premium gate lives even further up, on the period
/// pickers' "свой период" row itself (see PeriodPickerSheet), so this
/// screen assumes it's premium by the time someone's here. What
/// actually happens with the result (open a live WrappedScreen; for
/// StatsScreen, just switch its own scope in place) is entirely up to
/// that caller — this screen only ever names and saves one.
class CustomWrappedSetupScreen extends StatefulWidget {
  const CustomWrappedSetupScreen({super.key});

  @override
  State<CustomWrappedSetupScreen> createState() => _CustomWrappedSetupScreenState();
}

class _CustomWrappedSetupScreenState extends State<CustomWrappedSetupScreen> {
  final _titleController = TextEditingController();
  DateTimeRange? _range;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(const Duration(days: 13)), end: now),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'give it a name first'.tr);
      return;
    }
    final range = _range;
    if (range == null) {
      setState(() => _error = 'pick a date range too'.tr);
      return;
    }
    setState(() => _error = null);
    final period = await context.read<SavedPeriodsService>().add(title: title, range: range);
    if (!mounted) return;
    Navigator.of(context).pop(period);
  }

  String _rangeLabel() => _range == null ? 'choose start and end'.tr : CustomWrappedService.rangeLabel(_range!);

  @override
  Widget build(BuildContext context) {
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                      decoration: ClayBoxDecoration(
                        color: SeenlyPalette.accent,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: SeenlyPalette.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accentOnAccent.withOpacity(0.16),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.calendar_month_outlined, size: 21, color: SeenlyPalette.accentOnAccent),
                          ),
                          const SizedBox(height: 16),
                          Text('a wrapped of your own'.tr,
                              style: SeenlyText.serif(
                                  italic: true, size: 22, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
                          const SizedBox(height: 6),
                          Text('a trip, a season, a relationship — any stretch you name'.tr,
                              style: SeenlyText.serif(size: 13, color: SeenlyPalette.accentOnAccent.withOpacity(0.85))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('what should we call it?'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: ClayBoxDecoration(
                        boxShadow: SeenlyPalette.flatCardShadow,
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: SeenlyPalette.border),
                      ),
                      child: TextField(
                        controller: _titleController,
                        style: SeenlyText.serif(size: 14, italic: true),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                          border: InputBorder.none,
                          hintText: 'vacation in turkey'.tr,
                          hintStyle: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('which dates?'.tr, style: SeenlyText.metaLabel.copyWith(letterSpacing: 0.6)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: ClayBoxDecoration(
                          boxShadow: SeenlyPalette.flatCardShadow,
                          color: SeenlyPalette.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: SeenlyPalette.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_outlined, size: 17, color: SeenlyPalette.inkMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _rangeLabel(),
                                style: SeenlyText.serif(
                                    size: 13.5,
                                    color: _range == null ? SeenlyPalette.placeholder : SeenlyPalette.ink),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 17, color: SeenlyPalette.inkFaint),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
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
                    onTap: _submit,
                    scaleTo: 0.97,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(26)),
                      alignment: Alignment.center,
                      child: Text('make my wrapped'.tr,
                          style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.accentOnAccent)),
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
