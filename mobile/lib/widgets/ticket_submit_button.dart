import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../widgets/themed_loading_indicator.dart';

/// The "save this evening" button, dressed as a little ticket rather than
/// a plain pill — small bites taken out of both long edges and a soft
/// perforation line near the right end (where the icon sits), so it
/// quietly rhymes with [TicketWidget] and the tear-it-open moment that
/// follows a save, instead of looking like every other button on the
/// screen.
class TicketSubmitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const TicketSubmitButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  static const double _notchR = 7;
  static const double _stubWidth = 46;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: ClipPath(
          clipper: const _TicketButtonClipper(notchRadius: _notchR),
          child: Container(
            color: SeenlyPalette.accent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The soft perforation, standing in for a tear line — a
                // gentle nod to "this is a ticket," not a functional
                // control, so it's drawn quietly rather than announced.
                Positioned(
                  right: _stubWidth,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    painter: _DashedLinePainter(
                      color: SeenlyPalette.accentOnAccent.withOpacity(0.3),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: _stubWidth, left: 24),
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: ThemedLoadingIndicator(
                              strokeWidth: 2,
                              color: SeenlyPalette.accentOnAccent,
                            ),
                          )
                        : Text(
                            label,
                            style: SeenlyText.serif(
                                italic: true,
                                size: 14,
                                color: SeenlyPalette.accentOnAccent),
                          ),
                  ),
                ),
                Positioned(
                  right: 0,
                  width: _stubWidth,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Transform.rotate(
                      angle: -0.09, // just enough tilt to feel tucked in, not straightened by a ruler
                      child: Icon(
                        Icons.confirmation_number_outlined,
                        size: 20,
                        color: SeenlyPalette.accentOnAccent.withOpacity(0.85),
                      ),
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

/// Rounded rect with a small circular bite out of the vertical middle of
/// each long edge — same notch language as [TicketWidget], just one piece
/// instead of a body-and-stub pair, since nothing here actually tears.
class _TicketButtonClipper extends CustomClipper<Path> {
  final double notchRadius;
  const _TicketButtonClipper({required this.notchRadius});

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(16)));
    final notches = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(0, size.height / 2), radius: notchRadius))
      ..addOval(Rect.fromCircle(
          center: Offset(size.width, size.height / 2), radius: notchRadius));
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(covariant _TicketButtonClipper oldDelegate) =>
      oldDelegate.notchRadius != notchRadius;
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  static const double _dashHeight = 4;
  static const double _gapHeight = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    var y = 0.0;
    // size here is the actual box CustomPaint was laid out into — the
    // surrounding Positioned pins top and bottom, so this is already a
    // real, finite height by the time paint() runs.
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + _dashHeight), paint);
      y += _dashHeight + _gapHeight;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
