import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/locale_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// One selectable entry in the region picker. `code` is the ISO-3166
/// country code TMDB/JustWatch expects (see backend/app/routers/watch.py);
/// `null` means "auto" — guess from the device's own locale instead of a
/// fixed country (title_detail_screen.dart's _watchRegion).
class RegionOption {
  final String? code;
  final String label;
  const RegionOption(this.code, this.label);
}

/// Deliberately not every ISO country — just the ones someone here is
/// actually likely to want, so the list stays scannable. "auto" first,
/// then alphabetical by label. Add more here if a specific country's
/// catalog keeps getting asked for.
const List<RegionOption> kRegionOptions = [
  RegionOption(null, 'auto (use device region)'),
  RegionOption('AU', 'Australia'),
  RegionOption('BY', 'Belarus'),
  RegionOption('BR', 'Brazil'),
  RegionOption('CA', 'Canada'),
  RegionOption('FR', 'France'),
  RegionOption('DE', 'Germany'),
  RegionOption('IN', 'India'),
  RegionOption('IT', 'Italy'),
  RegionOption('JP', 'Japan'),
  RegionOption('KZ', 'Kazakhstan'),
  RegionOption('KR', 'South Korea'),
  RegionOption('PL', 'Poland'),
  RegionOption('RU', 'Russia'),
  RegionOption('ES', 'Spain'),
  RegionOption('TR', 'Turkey'),
  RegionOption('UA', 'Ukraine'),
  RegionOption('GB', 'United Kingdom'),
  RegionOption('US', 'United States'),
];

/// A simple list to pick which country's streaming availability shows on
/// a title (LocaleService.region) — opened from Settings, and from the
/// "where to watch" section itself when a title has nothing to show for
/// the current region.
Future<void> showRegionPickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _RegionPickerSheet(),
  );
}

class _RegionPickerSheet extends StatelessWidget {
  const _RegionPickerSheet();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: SeenlyPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('region'.tr, style: SeenlyText.serif(italic: true, size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              "which country's streaming info a title shows — change this anytime, it never touches what's already in your diary.".tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: kRegionOptions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final option = kRegionOptions[i];
                  final selected = option.code == locale.region;
                  return GestureDetector(
                    onTap: () {
                      context.read<LocaleService>().setRegion(option.code);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? SeenlyPalette.accent.withOpacity(0.10) : SeenlyPalette.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? SeenlyPalette.accent : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(option.label,
                                style: SeenlyText.serif(
                                  size: 13.5,
                                  color: selected ? SeenlyPalette.ink : SeenlyPalette.inkMuted,
                                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                                )),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle, size: 17, color: SeenlyPalette.accent),
                        ],
                      ),
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
