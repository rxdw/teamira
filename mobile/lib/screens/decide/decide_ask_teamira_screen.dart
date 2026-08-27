import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart';
import '../home/ask_teamira_results_screen.dart';
import 'decide_filters_screen.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';

/// "Ask teamira" as one of the four decision methods — same free-text
/// search as Home's own card ([AskTeamiraResultsScreen]), just opened
/// with a starting sentence built from whatever was picked on
/// [DecideFiltersScreen], so the filters chosen a step ago aren't wasted
/// even though Teamira's search itself is a plain string, not a
/// structured query. Fully editable before sending.
///
/// A proper "compose" screen rather than one strip of text on empty
/// paper: a shimmering hero badge up top, a real multi-line text area
/// that lights up on focus, and a clean stacked list of tappable
/// example prompts below it — mixing a couple built from the actual
/// filters with a few generic moods — so someone with no idea what to
/// type has somewhere to start besides the one pre-filled sentence.
class DecideAskTeamiraScreen extends StatefulWidget {
  final DecideFilters filters;
  // Overrides which results screen "find matches" opens — co-viewing's
  // own ask-teamira entry (see co_view_ask_teamira_screen.dart) passes
  // its own results screen here so a pick can be proposed to the whole
  // circle instead of just opening this account's title detail page.
  // Left null for the solo entry, which keeps opening Home's own
  // [AskTeamiraResultsScreen] exactly as before.
  final Widget Function(String query)? resultsBuilder;
  const DecideAskTeamiraScreen({super.key, required this.filters, this.resultsBuilder});

  @override
  State<DecideAskTeamiraScreen> createState() => _DecideAskTeamiraScreenState();
}

class _DecideAskTeamiraScreenState extends State<DecideAskTeamiraScreen> {
  late final _controller = TextEditingController(text: _suggestedQuery(widget.filters));
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  static String _typeWord(DecideFilters filters) {
    return filters.types.length == 1 ? _singular(filters.types.first) : 'something'.tr;
  }

  static String _suggestedQuery(DecideFilters filters) {
    final bits = <String>[];
    if (filters.decade != null) bits.add(decadeLabel(filters.decade!));
    if (filters.genres.isNotEmpty) bits.add(filters.genres.map((g) => g.toLowerCase()).join('/'));
    bits.add(_typeWord(filters));
    final noun = bits.join(' ');
    return LocaleService.appIsRussian ? '$noun ${'for tonight'.tr}' : 'a $noun for tonight';
  }

  static String _singular(String type) {
    switch (type) {
      case 'movie':
        return 'movie'.tr;
      case 'series':
        return 'series'.tr;
      case 'anime':
        return 'anime'.tr;
      case 'book':
        return 'book'.tr;
      case 'manga':
        return 'manga'.tr;
      case 'game':
        return 'game'.tr;
      default:
        return type;
    }
  }

  /// A handful of tappable starting points — one or two built from the
  /// filters already picked (a genre-flavored mood, a decade-flavored
  /// one), padded out with generic moods that work regardless of what
  /// was filtered, so the row never looks thin just because the pool
  /// happened to have no genre selected.
  List<String> get _examples {
    final filters = widget.filters;
    final typeWord = _typeWord(filters);
    final examples = <String>[];
    if (filters.genres.isNotEmpty) {
      final genre = filters.genres.first.toLowerCase();
      final phrase = '$genre $typeWord ${'that doesn\'t take itself too seriously'.tr}';
      examples.add(LocaleService.appIsRussian ? phrase : 'a $phrase');
    }
    if (filters.decade != null) {
      examples.add('${decadeLabel(filters.decade!)} ${'comfort watch, nothing heavy'.tr}');
    }
    examples.addAll([
      'something to make me cry'.tr,
      'fast-paced, keeps me hooked'.tr,
      'like [a title I loved]'.tr,
      'weird and mind-bending'.tr,
      'easy background while I cook'.tr,
      'short, I only have an hour'.tr,
    ]);
    return examples;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Fills the field with one of [_examples]. When the tapped example is
  /// a template like "like [a title I loved]", the bracketed placeholder
  /// is selected rather than the cursor just landing at the end — so
  /// typing immediately replaces it with a real title instead of someone
  /// tapping "find matches" with the literal brackets still in there
  /// (which the backend can't resolve to anything and would otherwise
  /// just be handed to it as extra noise).
  void _useExample(String text) {
    final placeholder = RegExp(r'\[[^\]]*\]').firstMatch(text);
    final selection = placeholder != null
        ? TextSelection(baseOffset: placeholder.start, extentOffset: placeholder.end)
        : TextSelection.collapsed(offset: text.length);
    _controller.value = TextEditingValue(text: text, selection: selection);
    _focusNode.requestFocus();
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => widget.resultsBuilder != null
            ? widget.resultsBuilder!(query)
            : AskTeamiraResultsScreen(query: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: SeenlyPalette.paper, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('ask teamira'.tr, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                child: Entrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 18),
                      Center(child: _ShimmerHero()),
                      const SizedBox(height: 18),
                      Text(
                        'here\'s a starting point — change it, or send it as is'.tr,
                        textAlign: TextAlign.center,
                        style: SeenlyText.serif(size: 14.5, color: SeenlyPalette.inkMuted),
                      ),
                      const SizedBox(height: 20),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                        decoration: BoxDecoration(
                          color: SeenlyPalette.paper,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: focused ? SeenlyPalette.periwinkle : SeenlyPalette.border,
                            width: focused ? 1.6 : 1,
                          ),
                          boxShadow: focused
                              ? [BoxShadow(color: SeenlyPalette.periwinkle.withOpacity(0.16), blurRadius: 20, offset: const Offset(0, 8))]
                              : null,
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 3,
                          maxLines: 6,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          style: SeenlyText.serif(size: 15.5),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text('or try one of these'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: SeenlyPalette.paper,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: SeenlyPalette.border),
                          boxShadow: SeenlyPalette.softShadow,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (int i = 0; i < _examples.length; i++) ...[
                              if (i > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 50),
                                  child: Container(height: 1, color: SeenlyPalette.border),
                                ),
                              _ExampleRow(text: _examples[i], onTap: () => _useExample(_examples[i])),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: PrimaryButton(label: 'find matches'.tr, onTap: _submit),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable prompt in the "or try one of these" list — full-width
/// rows sharing a single card (see the Container around this in build())
/// with a hairline divider between them, rather than each suggestion
/// being its own separately-bordered box: one grouped list reads as one
/// deliberate piece of UI, where seven identical little cards in a row
/// just reads as clutter repeated seven times. The small periwinkle
/// sparkle badge echoes [_ShimmerHero] above, so the whole screen feels
/// like one idea (teamira's own accent color) rather than a generic
/// chevron list.
class _ExampleRow extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _ExampleRow({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: SeenlyPalette.periwinkle.withOpacity(0.06),
        splashColor: SeenlyPalette.periwinkle.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SeenlyPalette.periwinkle.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_outlined, size: 12, color: SeenlyPalette.periwinkle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: SeenlyText.serif(size: 13.5, color: SeenlyPalette.ink)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: SeenlyPalette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screen's one hero flourish: a soft ambient halo behind a
/// shimmering sparkle badge — teamira "thinking" before anyone's even
/// typed anything, rather than a small static icon sitting alone at the
/// top of a lot of empty paper.
class _ShimmerHero extends StatelessWidget {
  static const double _size = 84;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 40,
      height: _size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              width: _size + 40,
              height: _size + 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [SeenlyPalette.periwinkle.withOpacity(0.20), SeenlyPalette.periwinkle.withOpacity(0)],
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(_size / 2),
            child: ShimmerBlock(
              width: _size,
              height: _size,
              borderRadius: BorderRadius.circular(_size / 2),
              baseColor: Color.alphaBlend(SeenlyPalette.periwinkle.withOpacity(0.30), SeenlyPalette.paper),
              highlightColor: SeenlyPalette.paper,
            ),
          ),
          Icon(Icons.auto_awesome_outlined, size: 34, color: SeenlyPalette.periwinkle),
        ],
      ),
    );
  }
}
