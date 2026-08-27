import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// An iOS-style "slide to confirm" control — the same idea as the lock
/// screen's "slide to power off": a full-width track with a thumb the
/// person has to physically drag to the far edge before anything
/// happens. Releasing short of the end springs the thumb straight back
/// to the start and nothing fires. Meant for actions that are
/// irreversible or annoying to undo (like abandoning a route in
/// progress), where a single accidental tap should never be enough.
class SlideToConfirm extends StatefulWidget {
  final String label;
  final String confirmedLabel;
  Color get accent => _accent ?? SeenlyPalette.coral;
  final Color? _accent;
  Color get trackColor => _trackColor ?? SeenlyPalette.background;
  final Color? _trackColor;
  Color get labelColor => _labelColor ?? SeenlyPalette.inkMuted;
  final Color? _labelColor;
  final IconData icon;
  final VoidCallback onConfirmed;

  SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmedLabel = 'done',
    Color? accent,
    Color? trackColor,
    Color? labelColor,
    this.icon = Icons.chevron_right_rounded,
  })  : _accent = accent,
        _trackColor = trackColor,
        _labelColor = labelColor;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addListener(() {
      if (_snapAnimation != null) setState(() => _dragX = _snapAnimation!.value);
    });
  Animation<double>? _snapAnimation;

  double _dragX = 0;
  double _maxDrag = 1;
  bool _confirmed = false;

  static const double _thumbSize = 48;
  static const double _trackPad = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_confirmed) return;
    setState(() => _dragX = (_dragX + details.delta.dx).clamp(0, _maxDrag));
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_confirmed) return;
    final completed = _maxDrag > 0 && _dragX >= _maxDrag * 0.72;
    if (completed) {
      setState(() => _confirmed = true);
      await _snapTo(_maxDrag);
      widget.onConfirmed();
    } else {
      await _snapTo(0);
    }
  }

  Future<void> _snapTo(double target) {
    _snapAnimation = Tween<double>(begin: _dragX, end: target)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    return _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _maxDrag = (constraints.maxWidth - _thumbSize - _trackPad * 2).clamp(0, double.infinity);
      final t = _maxDrag == 0 ? 0.0 : (_dragX / _maxDrag).clamp(0, 1);
      final trackHeight = _thumbSize + _trackPad * 2;

      return GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Container(
          height: trackHeight,
          decoration: BoxDecoration(
            color: widget.trackColor,
            borderRadius: BorderRadius.circular(trackHeight / 2),
            border: Border.all(color: widget.accent.withOpacity(0.22)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Fill behind the thumb, growing as it's dragged along.
              Positioned(
                left: _trackPad,
                top: _trackPad,
                bottom: _trackPad,
                width: _dragX + _thumbSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.accent.withOpacity(0.14 + 0.22 * t),
                    borderRadius: BorderRadius.circular(_thumbSize / 2),
                  ),
                ),
              ),
              // Centered label, fading as the thumb slides over it.
              Positioned.fill(
                child: Center(
                  child: Opacity(
                    opacity: (1 - t * 1.7).clamp(0, 1),
                    child: Text(
                      _confirmed ? widget.confirmedLabel : widget.label,
                      style: SeenlyText.mono(size: 11, color: widget.labelColor, weight: FontWeight.w600)
                          .copyWith(letterSpacing: 0.6),
                    ),
                  ),
                ),
              ),
              // The thumb itself.
              Positioned(
                left: _trackPad + _dragX,
                top: _trackPad,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: widget.accent.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Icon(
                    _confirmed ? Icons.check_rounded : widget.icon,
                    color: SeenlyPalette.paper,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
