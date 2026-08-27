import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../widgets/themed_loading_indicator.dart';

/// The "save this evening" button in the shuttle theme — a small
/// rocket-launch pill, the same rhythm as [TicketSubmitButton]'s
/// tear-line, [CoachSubmitButton]'s coach icon, and
/// [GardenSubmitButton]'s bud: a small nod to the theme, not a
/// functional control on its own.
class ShuttleSubmitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const ShuttleSubmitButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            color: SeenlyPalette.accent,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rocket_launch_outlined, size: 17, color: SeenlyPalette.accentOnAccent.withOpacity(0.9)),
                    const SizedBox(width: 9),
                    Text(
                      label,
                      style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
