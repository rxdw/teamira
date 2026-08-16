import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/interest_picker.dart';
import '../../widgets/small_pieces.dart';
import '../../services/app_translations.dart';

/// Lets a person pick what Collections should gather for them.
///
/// Used two ways from [CollectionsScreen]:
/// - **First run** (`isFirstRun: true`): rendered inline in place of the
///   feed, no way to dismiss without choosing — this *is* the first thing
///   a new visitor to the tab sees.
/// - **Revisit** (`isFirstRun: false`): pushed as a normal screen from the
///   little icon in the collections header, pre-filled with whatever was
///   chosen last time, poppable at any point since a choice already exists.
///
/// The same card list (see widgets/interest_picker.dart) also appears
/// inside onboarding's own interests step, so a person only ever sees one
/// design for "what should we gather for you?" — onboarding just saves
/// through the same CollectionsPrefsService this screen reads from, so
/// landing here afterward never asks again.
class CollectionInterestsScreen extends StatefulWidget {
  final bool isFirstRun;
  final Set<String> initialSelected;
  final ValueChanged<Set<String>> onSave;

  const CollectionInterestsScreen({
    super.key,
    required this.isFirstRun,
    required this.initialSelected,
    required this.onSave,
  });

  @override
  State<CollectionInterestsScreen> createState() =>
      _CollectionInterestsScreenState();
}

class _CollectionInterestsScreenState extends State<CollectionInterestsScreen> {
  late Set<String> _selected = {...widget.initialSelected};

  void _save() {
    widget.onSave(_selected);
    if (!widget.isFirstRun) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        children: [
          if (!widget.isFirstRun)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back, size: 16, color: SeenlyPalette.inkFaint),
                    const SizedBox(width: 6),
                    Text('back to collections'.tr,
                        style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ),
          Text(
            widget.isFirstRun ? 'what should we gather for you?' : 'your interests',
            style: SeenlyText.screenTitle,
          ),
          const SizedBox(height: 8),
          Text(
            widget.isFirstRun
                ? 'pick a few things you\'re into — collections will lead with those. you can always change your mind later.'
                : 'change what collections leads with, any time.',
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkFaint),
          ),
          const SizedBox(height: 26),
          for (final interest in kInterests) ...[
            InterestPickerRow(
              interest: interest,
              selected: _selected.contains(interest.value),
              onTap: interest.soon
                  ? null
                  : () => setState(() {
                        if (_selected.contains(interest.value)) {
                          _selected.remove(interest.value);
                        } else {
                          _selected.add(interest.value);
                        }
                      }),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: widget.isFirstRun
                ? (_selected.isEmpty ? 'show me everything' : 'take me to my shelf')
                : 'save',
            onTap: _save,
          ),
          if (widget.isFirstRun) ...[
            const SizedBox(height: 12),
            Center(
              child: Text('nothing picked yet is fine too — you can decide later'.tr,
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
            ),
          ],
        ],
      ),
    );

    // First run replaces the tab's content in place, so it shouldn't carry
    // its own Scaffold background — it already sits on one. Revisits are a
    // pushed route and need their own.
    if (widget.isFirstRun) {
      return Container(color: SeenlyPalette.background, child: body);
    }
    return Scaffold(backgroundColor: SeenlyPalette.background, body: body);
  }
}
