import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// A soft cover over text that might spoil something — blurred rather
/// than hidden outright, with a small paper chip floating on top
/// inviting a tap. Once tapped it stays revealed for as long as this
/// widget is alive (this screen/sheet visit); it veils again next time,
/// which is the point — nobody has to remember to re-hide anything.
///
/// When [active] is false this is a no-op and just returns [child] —
/// callers pass the relevant SpoilerPrefsService flag
/// (blurDescriptions / blurReviews) straight through, so the veil only
/// ever shows up where and when the person actually wants it.
class SpoilerVeil extends StatefulWidget {
  final Widget child;
  final bool active;
  final String label;

  const SpoilerVeil({
    super.key,
    required this.child,
    required this.active,
    this.label = 'might give things away',
  });

  @override
  State<SpoilerVeil> createState() => _SpoilerVeilState();
}

class _SpoilerVeilState extends State<SpoilerVeil> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _revealed) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _revealed = true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: widget.child,
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: SeenlyPalette.paper.withOpacity(0.5)),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SeenlyPalette.dashedBorder),
                    boxShadow: [
                      BoxShadow(
                        color: SeenlyPalette.ink.withOpacity(0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_outlined, size: 16, color: SeenlyPalette.inkMuted),
                      const SizedBox(height: 5),
                      Text(widget.label.tr,
                          style: SeenlyText.serif(size: 11.5, italic: true, color: SeenlyPalette.inkMuted)),
                      const SizedBox(height: 3),
                      Text('tap to reveal'.tr,
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent, weight: FontWeight.w600)),
                    ],
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
