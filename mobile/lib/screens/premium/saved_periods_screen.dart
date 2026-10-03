import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/saved_wrapped_period.dart';
import '../../services/app_translations.dart';
import '../../services/custom_wrapped_service.dart';
import '../../services/locale_service.dart';
import '../../services/saved_periods_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import 'custom_wrapped_setup_screen.dart';
import '../../theme/clay_kit.dart';

/// The actual "свой период" landing page — every named date range the
/// person has saved (see SavedPeriodsService), each one handed straight
/// back to whoever opened this screen without retyping a title or
/// re-picking dates. Always resolves with a [SavedWrappedPeriod] (from
/// tapping a saved one, or from naming a brand new one via the "+" —
/// see [CustomWrappedSetupScreen]) or `null` if the person backs out —
/// what happens with that period (open WrappedScreen; for
/// StatsScreen, just switch its own scope in place) is entirely up to
/// the caller, same "this screen only picks, it doesn't act" shape as
/// PeriodPickerSheet itself.
///
/// Reached only from a "свой период" row (see PeriodPickerSheet in
/// wrapped_screen.dart, or StatsScreen's own scope switcher), which is
/// where the premium gate already lives — this screen, like
/// CustomWrappedSetupScreen, assumes it's premium by the time someone's
/// here.
class SavedPeriodsScreen extends StatelessWidget {
  const SavedPeriodsScreen({super.key});

  Future<void> _openNew(BuildContext context) async {
    final period = await Navigator.of(context)
        .push<SavedWrappedPeriod>(MaterialPageRoute(builder: (_) => const CustomWrappedSetupScreen()));
    // Naming a new one and immediately using it should feel like one
    // step, not two — bubble straight back to whoever opened this
    // screen instead of returning to the list first.
    if (period != null && context.mounted) Navigator.of(context).pop(period);
  }

  Future<void> _confirmDelete(BuildContext context, SavedWrappedPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('delete this period?'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
        content: Text(
          LocaleService.appIsRussian ? '«${period.title}» пропадёт из этого списка' : '"${period.title}" will disappear from this list',
          style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr, style: SeenlyText.mono(size: 13, color: SeenlyPalette.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('delete'.tr, style: SeenlyText.mono(size: 13, color: SeenlyPalette.coral, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<SavedPeriodsService>().remove(period.id);
    }
  }

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
                  Expanded(
                    child: Text('your periods'.tr,
                        textAlign: TextAlign.center, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, size: 22, color: SeenlyPalette.accent),
                    onPressed: () => _openNew(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<SavedPeriodsService>(
                builder: (context, service, _) {
                  final periods = service.periods;
                  if (periods.isEmpty) {
                    return _EmptyState(onNew: () => _openNew(context));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                    itemCount: periods.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _PeriodCard(
                      period: periods[i],
                      onTap: () => Navigator.of(context).pop(periods[i]),
                      onDelete: () => _confirmDelete(context, periods[i]),
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 34, color: SeenlyPalette.inkFaint),
            const SizedBox(height: 16),
            Text(
              LocaleService.appIsRussian ? 'пока ни одного своего периода' : 'no periods of your own yet',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(italic: true, size: 16, color: SeenlyPalette.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'a trip, a season, a relationship — any stretch you name'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 22),
            PressScale(
              onTap: onNew,
              scaleTo: 0.97,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(24)),
                child: Text('name a new period'.tr,
                    style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final SavedWrappedPeriod period;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PeriodCard({required this.period, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.98,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(18),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: SeenlyPalette.accent.withOpacity(0.1), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(Icons.calendar_month_outlined, size: 18, color: SeenlyPalette.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(period.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600, color: SeenlyPalette.ink)),
                  const SizedBox(height: 2),
                  Text(CustomWrappedService.rangeLabel(period.range),
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: SeenlyPalette.inkFaint),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
