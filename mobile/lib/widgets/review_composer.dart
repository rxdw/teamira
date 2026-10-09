import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/seenly_skin.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// A full-page, distraction-free spot for writing (or reading) a long
/// review — reached from the small "a note to your future self" box in
/// every themed log flow (cinema/coach/garden), from the "edit this
/// evening" sheet's own review field, and from the series sheet's
/// review section, whenever a few lines feels too tight for what
/// someone wants to say about something. It's not a second place the
/// review lives — just a roomier view onto the exact same text the
/// small box holds, so there's no separate save step here: closing it
/// (the arrow, or the system back gesture) always hands back whatever
/// is currently typed, same as tapping out of the small box would.
/// Nothing to lose by opening it, nothing extra to confirm before
/// leaving it.
///
/// [readOnly] turns it into a plain reader instead — what
/// [WatchedPreviewCard] opens once a review runs past its own short
/// preview (see watched_preview_sheet.dart), so someone can read the
/// whole thing without it needing to fit inside that small floating
/// card.
Future<String?> showReviewComposer(
  BuildContext context, {
  required String initialText,
  required String forTitle,
  bool readOnly = false,
}) {
  return Navigator.of(context).push<String?>(
    MaterialPageRoute(
      builder: (_) => _ReviewComposerScreen(
        initialText: initialText,
        forTitle: forTitle,
        readOnly: readOnly,
      ),
    ),
  );
}

class _ReviewComposerScreen extends StatefulWidget {
  final String initialText;
  final String forTitle;
  final bool readOnly;

  const _ReviewComposerScreen({
    required this.initialText,
    required this.forTitle,
    required this.readOnly,
  });

  @override
  State<_ReviewComposerScreen> createState() => _ReviewComposerScreenState();
}

class _ReviewComposerScreenState extends State<_ReviewComposerScreen> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  late int _wordCount = _countWords(widget.initialText);

  static int _countWords(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.readOnly) {
      _controller.addListener(() {
        final next = _countWords(_controller.text);
        if (next != _wordCount) setState(() => _wordCount = next);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Same "no separate save step" reasoning as the class doc above —
      // the system back gesture hands back the current draft too, not
      // just the explicit arrow button.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_controller.text);
      },
      child: Scaffold(
        backgroundColor: SeenlyPalette.background,
        appBar: AppBar(
          backgroundColor: SeenlyPalette.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: SeenlyPalette.ink),
            onPressed: _close,
          ),
          title: Text(
            widget.forTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.readOnly ? 'the review'.tr : 'your review',
                  style: SeenlyText.serif(
                      size: 20, weight: FontWeight.w600, italic: true, color: SeenlyPalette.accent),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.readOnly
                      ? 'every word of it'.tr
                      : 'as long as you want — nobody\'s reading over your shoulder'.tr,
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: TextField(
                      controller: _controller,
                      readOnly: widget.readOnly,
                      autofocus: !widget.readOnly,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: SeenlyText.serif(italic: true, size: 15.5, color: SeenlyPalette.ink),
                      cursorColor: SeenlyPalette.accent,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: 'what stayed with you?'.tr,
                        hintStyle: SeenlyText.serif(italic: true, size: 15.5, color: SeenlyPalette.placeholder),
                      ),
                    ),
                  ),
                ),
                if (!widget.readOnly && _wordCount > 0) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      nCount('nWords', _wordCount),
                      style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small "expand to a full page" link dropped under every quick
/// note box (log flows' "a note to your future self", the edit
/// sheet's "review" field) — same minimal text-link language as
/// [SectionHeader]'s trailing links elsewhere in the app, not a full
/// button, so it reads as an option rather than competing with the box
/// itself for attention.
class ExpandReviewLink extends StatelessWidget {
  final VoidCallback onTap;
  const ExpandReviewLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Cozy skin swaps the plain "expand" icon for a pushpin — the
    // little "pin a longer note to the page" gesture from the pastel
    // mockups, tapped to the exact same full-page composer either way.
    final icon = SeenlySkin.isCozy ? Icons.push_pin_outlined : Icons.open_in_full;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: SeenlyPalette.accent),
            const SizedBox(width: 5),
            Text('write more, full page'.tr,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent)),
          ],
        ),
      ),
    );
  }
}
