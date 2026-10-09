import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// What stayed with you when the evening landed — the preset list shown
/// whenever there's no rating yet, or the rating is a good one (see
/// [isLowRatingForVibe]). Not exhaustive, just enough that most evenings
/// can be tagged in one tap. Anything else goes through the free-text
/// field below and becomes its own chip.
const List<String> kPresetLoveTags = [
  'the music',
  'the ending',
  'the atmosphere',
  'the performances',
  'the visuals',
  'the story',
  'the humor',
  'the pacing',
];

/// The mirror list for a rougher evening (rating below 5) — what fell
/// short instead of what stood out. Swapped in automatically by
/// [vibePresetTags]/[MoodTagPicker] whenever [isLowRatingForVibe] is true.
const List<String> kPresetDislikeTags = [
  'the ending',
  'the pacing',
  'saw it coming',
  'flat characters',
  'style over substance',
  'ran too long',
  'the tone',
  'forgettable',
];

/// A rating below 5 (out of the app's 1–10 scale) reads as a rougher
/// evening — anywhere the vibe step needs to pick between "why did you
/// love this" and "what fell short" phrasing/tags, this is the one
/// rating check to reuse. `0` (not yet rated) still counts as the warmer
/// default.
bool isLowRatingForVibe(int rating) => rating > 0 && rating < 5;

/// The preset tag set to show for a given rating — see
/// [isLowRatingForVibe].
List<String> vibePresetTags(int rating) =>
    isLowRatingForVibe(rating) ? kPresetDislikeTags : kPresetLoveTags;

/// The headline for the vibe step for a given rating — see
/// [isLowRatingForVibe].
String vibePromptTitle(int rating) =>
    isLowRatingForVibe(rating) ? "what fell short?".tr : 'why did you love this?'.tr;

/// Lets the person pick from a preset list of "why did you love this" (or,
/// for a rough rating, "what fell short") tags and add their own free-text
/// ones — both live in the same flat `selected` list, since the diary
/// doesn't distinguish "preset" from "custom" once saved.
class MoodTagPicker extends StatefulWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  // Drives which preset list shows — see [vibePresetTags]. Defaults to 0
  // (not yet rated), which reads as the warmer "why did you love this"
  // list.
  final int rating;

  const MoodTagPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.rating = 0,
  });

  @override
  State<MoodTagPicker> createState() => _MoodTagPickerState();
}

class _MoodTagPickerState extends State<MoodTagPicker> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    final next = List<String>.from(widget.selected);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    widget.onChanged(next);
  }

  void _addCustom() {
    final raw = _customController.text.trim();
    if (raw.isEmpty) return;
    if (!widget.selected.contains(raw)) {
      widget.onChanged([...widget.selected, raw]);
    }
    _customController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final presetTags = vibePresetTags(widget.rating);
    // Custom tags the person has typed in that aren't part of the preset
    // list — shown alongside it so they can still tap to remove one.
    final customSelected =
        widget.selected.where((t) => !presetTags.contains(t)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in presetTags)
              PillChip(
                label: tag,
                active: widget.selected.contains(tag),
                onTap: () => _toggle(tag),
              ),
            for (final tag in customSelected)
              PillChip(
                label: tag,
                active: true,
                onTap: () => _toggle(tag),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: ClayBoxDecoration(
                  boxShadow: SeenlyPalette.flatCardShadow,
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _customController,
                  style: SeenlyText.bodyText,
                  onSubmitted: (_) => _addCustom(),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'your own tag...'.tr,
                    hintStyle: SeenlyText.serif(color: SeenlyPalette.placeholder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addCustom,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SeenlyPalette.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add,
                    size: 18, color: SeenlyPalette.accentOnAccent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
