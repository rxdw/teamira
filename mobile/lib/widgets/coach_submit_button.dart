import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../widgets/themed_loading_indicator.dart';

/// The "save this evening" button in the "Evening Route" theme — same
/// job as `TicketSubmitButton`, dressed as a tiny
/// train instead: it noses forward under a finger and gives a small
/// puff of exhaust dust the moment it's actually pressed, echoing the
/// pull-out that follows once the seat's picked.
class CoachSubmitButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const CoachSubmitButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  State<CoachSubmitButton> createState() => _CoachSubmitButtonState();
}

class _CoachSubmitButtonState extends State<CoachSubmitButton> with TickerProviderStateMixin {
  late final AnimationController _press;
  late final AnimationController _pullOut;

  static const double _stubWidth = 46;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _pullOut = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _press.dispose();
    _pullOut.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.loading || widget.onTap == null) return;
    _pullOut.forward(from: 0);
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
                            child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
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
                      animation: Listenable.merge([_press, _pullOut]),
                      builder: (context, _) {
                        final pressT = _press.value;
                        final pullT = _pullOut.value;
                        final nudge = pressT * 3;
                        final dustOpacity = pullT <= 0 ? 0.0 : (1 - pullT) * 0.5;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              right: 2,
                              child: Opacity(
                                opacity: dustOpacity.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(6 + pullT * 8, 0),
                                  child: Container(
                                    width: 5 + pullT * 4,
                                    height: 5 + pullT * 4,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: SeenlyPalette.accentOnAccent.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(-nudge, 0),
                              child: _TrainGlyph(color: SeenlyPalette.accentOnAccent.withOpacity(0.9)),
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

/// A tiny train — a body with a tapered nose, a small pantograph tick
/// on the roof, and wheels tucked close together — drawn from plain
/// shapes rather than borrowing a generic system icon, same spirit as
/// the other two themes' little hand-drawn glyphs.
class _TrainGlyph extends StatelessWidget {
  final Color color;
  const _TrainGlyph({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 18,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(width: 1.6, height: 4, color: color.withOpacity(0.85)),
          ),
          Positioned(
            top: 4,
            child: Container(
              width: 22,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                  topRight: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 6,
            child: Container(width: 4.5, height: 4.5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          ),
          Positioned(
            bottom: 0,
            right: 6,
            child: Container(width: 4.5, height: 4.5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          ),
        ],
      ),
    );
  }
}
