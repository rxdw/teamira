import 'package:flutter/material.dart';

import '../services/app_translations.dart';
import '../services/log_theme_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// "add to favorite films" toggle on the log form, right under the rating —
/// the same real favorite flag the title screen's heart button sets and
/// Profile's favorite films row reads (see WatchlistEntry.is_favorite on
/// the backend). Themed phrasing, same soft pink used for hearts elsewhere.
class FavoriteToggle extends StatelessWidget {
  final LogTheme theme;
  final bool value;
  final ValueChanged<bool> onChanged;
  const FavoriteToggle({
    super.key,
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  String get _label => switch (theme) {
        LogTheme.garden => 'keep this one in the garden'.tr,
        LogTheme.coach => 'keep this one for the road'.tr,
        LogTheme.ticket => 'keep this stub in your favorites'.tr,
        LogTheme.shuttle => 'keep this one in the log'.tr,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? SeenlyPalette.pink.withOpacity(0.1) : SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? SeenlyPalette.pink.withOpacity(0.45) : SeenlyPalette.border,
          ),
        ),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: value ? 1.15 : 1.0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: Icon(
                value ? Icons.favorite : Icons.favorite_border,
                size: 17,
                color: value ? SeenlyPalette.pink : SeenlyPalette.inkFaint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _label.tr,
                style: SeenlyText.serif(
                  italic: true,
                  size: 12.5,
                  color: value ? SeenlyPalette.pink : SeenlyPalette.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
