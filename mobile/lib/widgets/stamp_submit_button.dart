import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// The "save this evening" button in the passport theme — same job as
/// `TicketSubmitButton`, dressed as a little rubber stamp instead: a
/// plain rounded pill with a stamp-handle glyph that visibly presses
/// down under a finger and lets off a quick ink-ring pulse the moment
/// it's actually pressed, so the tap itself carries a little of the
/// same tactile pleasure as the stamping ritual that follows.
class StampSubmitButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const StampSubmitButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  State<StampSubmitButton> createState() => _StampSubmitButtonState();
}

class _StampSubmitButtonState extends State<StampSubmitButton> with TickerProviderStateMixin {
  late final AnimationController _press; // held down while a finger is on it
  late final AnimationController _thump; // one-shot ink ring on an actual tap

  static const double _stubWidth = 46;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _thump = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _press.dispose();
    _thump.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.loading || widget.onTap == null) return;
    _thump.forward(from: 0);
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
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: SeenlyPalette.accentOnAccent,
                            ),
                          )
                        : Text(
                            widget.label,
                            style: SeenlyText.serif(
                                italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
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
                      animation: Listenable.merge([_press, _thump]),
                      builder: (context, _) {
                        final pressT = _press.value;
                        final thumpT = _thump.value;
                        final ringOpacity = thumpT <= 0 ? 0.0 : (1 - thumpT) * 0.55;
                        final ringScale = 0.4 + thumpT * 1.1;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: ringOpacity.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: ringScale,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: SeenlyPalette.accentOnAccent.withOpacity(0.7),
                                        width: 1.4),
                                  ),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, pressT * 3),
                              child: Transform.scale(
                                scale: 1 - pressT * 0.12,
                                child: _StampGlyph(color: SeenlyPalette.accentOnAccent.withOpacity(0.9)),
                              ),
                            ),
                          ],
                        );
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

/// A tiny rubber-stamp handle — a narrow grip sitting on a wider base —
/// drawn from plain rounded blocks rather than borrowing a generic
/// system icon, same spirit as the ticket theme's little seat glyph.
class _StampGlyph extends StatelessWidget {
  final Color color;
  const _StampGlyph({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 9,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 1.5),
          Container(
            width: 20,
            height: 6,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ),
    );
  }
}
