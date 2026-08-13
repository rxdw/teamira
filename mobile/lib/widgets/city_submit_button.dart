import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// The "save this evening" button in the city theme — same job as the
/// other three themes' submit buttons, dressed as a tiny construction
/// crane instead: its hook dips down under a finger and lifts a small
/// beam into place the moment it's actually pressed, echoing the
/// building that's about to rise.
class CitySubmitButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const CitySubmitButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  State<CitySubmitButton> createState() => _CitySubmitButtonState();
}

class _CitySubmitButtonState extends State<CitySubmitButton> with TickerProviderStateMixin {
  late final AnimationController _press;
  late final AnimationController _lift;

  static const double _stubWidth = 46;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  }

  @override
  void dispose() {
    _press.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.loading || widget.onTap == null) return;
    _lift.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => _press.forward(),
        onTapUp: disabled ? null : (_) => _press.reverse(),
        onTapCancel: disabled ? null : () => _press.reverse(),
        onTap: disabled ? null : _handleTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: SeenlyPalette.accent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: _stubWidth, left: 24),
                  child: Center(
                    child: widget.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                          )
                        : Text(
                            widget.label,
                            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
                          ),
                  ),
                ),
                Positioned(
                  right: 0,
                  width: _stubWidth,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_press, _lift]),
                      builder: (context, _) {
                        final pressT = _press.value;
                        // The beam dips on press, then lifts and settles
                        // once the tap actually commits.
                        final liftT = _lift.value;
                        final beamY = pressT * 3 - (liftT < 1 ? liftT * 5 : 0);
                        return _CraneGlyph(color: SeenlyPalette.accentOnAccent.withOpacity(0.9), beamOffset: beamY);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny crane — an L-shaped arm over a small hanging beam — drawn
/// from plain rounded blocks rather than borrowing a generic system
/// icon, same spirit as the other three themes' hand-drawn glyphs.
class _CraneGlyph extends StatelessWidget {
  final Color color;
  final double beamOffset;

  const _CraneGlyph({required this.color, required this.beamOffset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        children: [
          Positioned(left: 2, top: 0, bottom: 2, child: Container(width: 2.4, color: color)),
          Positioned(left: 2, top: 0, child: Container(width: 16, height: 2.4, color: color)),
          Positioned(
            left: 14,
            top: 2 + beamOffset,
            child: Container(width: 1.4, height: 8, color: color.withOpacity(0.7)),
          ),
          Positioned(
            left: 10,
            top: 9 + beamOffset,
            child: Container(
              width: 9,
              height: 6,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
