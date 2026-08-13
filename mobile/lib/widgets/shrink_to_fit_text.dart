import 'package:flutter/material.dart';

/// A title that shrinks itself to fit — instead of truncating with an
/// ellipsis mid-word — wherever a poster/backdrop hands it a fixed box
/// to sit in (the title detail header banner, a poster tile's caption,
/// a card's name plate). Long titles like "Berserk: The Golden Age Arc
/// I — Egg of the King" used to just get chopped off after two lines
/// with "…"; this instead measures the text at the requested style's
/// size and steps the size down (half a point at a time) until the
/// whole thing lays out within [maxLines] at whatever width it's
/// actually given, only falling back to a normal ellipsis if it's
/// still too long once it hits [minFontSize] — so it never shrinks
/// past legibility, it just very rarely needs to.
class ShrinkToFitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final TextAlign textAlign;

  const ShrinkToFitText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
    this.minFontSize = 10,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var fontSize = style.fontSize ?? 14;
        if (maxWidth.isFinite && maxWidth > 0) {
          while (fontSize > minFontSize) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
              maxLines: maxLines,
              textDirection: Directionality.of(context),
              ellipsis: '…',
            )..layout(maxWidth: maxWidth);
            if (!painter.didExceedMaxLines) break;
            fontSize -= 0.5;
          }
        }
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style.copyWith(fontSize: fontSize),
        );
      },
    );
  }
}
