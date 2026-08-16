import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;
  // Optional overrides — when omitted, falls back to the usual
  // SeenlyText styles so every other screen using this widget is
  // untouched. Collections passes its own trial font through here.
  final TextStyle? titleStyle;
  final TextStyle? trailingStyle;
  // When true, the title sits centered across the full row width
  // instead of hugging the left edge — the trailing link still floats
  // at the right. Off by default so every other screen (home, diary,
  // profile) keeps its original left-aligned header.
  final bool centerTitle;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
    this.titleStyle,
    this.trailingStyle,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    // Collection names should always read in full — never truncated to
    // an ellipsis. FittedBox scales the whole line down just enough to
    // fit the space it's given instead of clipping it, so a long shelf
    // name shows up smaller rather than cut short. maxLines stays 1 so
    // FittedBox measures (and scales) a single line rather than letting
    // the text wrap first and then scaling the wrapped block.
    Widget shrinkToFit(String text, TextStyle? style, Alignment alignment) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(text, style: style, maxLines: 1),
      );
    }

    final titleStyleResolved = titleStyle ?? SeenlyText.sectionTitle;
    final trailingWidget = trailing == null
        ? null
        : GestureDetector(
            onTap: onTrailingTap,
            child: Text(trailing!,
                style: trailingStyle ??
                    SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
          );

    if (!centerTitle) {
      // Title sits in Expanded so it's the one that gives way (shrinks
      // to fit) if the row is tight — previously both title and
      // trailing claimed their full intrinsic width in the Row, which
      // is what let long titles push the trailing text past the right
      // edge instead of shrinking to make room.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
              child: shrinkToFit(
                  title, titleStyleResolved, Alignment.centerLeft)),
          if (trailingWidget != null) ...[
            const SizedBox(width: 8),
            trailingWidget,
          ],
        ],
      );
    }

    // Centered mode: the title centers in the space actually left over
    // once the trailing link/button claims its width — not across the
    // full row regardless of that width. A Stack with both Center'd
    // title and a right-pinned trailing (the previous approach) doesn't
    // know about each other's size at all, so a long title (e.g. "pick
    // something from your shelf") centers across the *whole* row and
    // runs straight into "shuffle ↻" instead of stopping short of it.
    // Mirroring an invisible copy of the trailing widget on the left
    // keeps the middle Expanded's centering symmetric — the title still
    // lines up with the true row center when it's short, and shrinks
    // instead of colliding when it's long enough to need the room.
    final centeredTitle =
        shrinkToFit(title, titleStyleResolved, Alignment.center);
    if (trailingWidget == null) {
      return Center(child: centeredTitle);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Opacity(opacity: 0, child: IgnorePointer(child: trailingWidget)),
        const SizedBox(width: 8),
        Expanded(child: Center(child: centeredTitle)),
        const SizedBox(width: 8),
        trailingWidget,
      ],
    );
  }
}
