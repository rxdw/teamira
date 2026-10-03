import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import 'co_view_hub_screen.dart';

/// A thin, pushed-route wrapper around [CoViewHubScreen].
///
/// This used to be its own full, separate implementation of co-viewing —
/// suggestions, "plan an evening", the planned/watched split, settings,
/// add-to-circle, all built again from scratch here, slowly drifting out
/// of sync with the tab-based version reached from Home's "вы и .."
/// switch (see screens/shell/home_mode_shell.dart). The two had ended up
/// showing different things for the same feature, which is exactly the
/// kind of split that confuses more than it helps.
///
/// They're unified now: [CoViewHubScreen] is the one real implementation,
/// and this class is just what's left of the old screen — a `Scaffold`
/// with a back arrow, for the entry points that push a route instead of
/// switching a tab (right now: the "co-viewing / linked with X" card on
/// Home, see screens/home/home_screen.dart's `_openCoViewing`). Whatever
/// reaches this screen sees exactly the same content, tabs and all, that
/// the embedded version shows.
class CoViewingScreen extends StatelessWidget {
  const CoViewingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: CoViewHubScreen(
          onBack: () => Navigator.of(context).pop(),
          // Home re-checks the link when this route returns (see
          // HomeScreen._openCoViewing), so closing is all that's needed.
          onUnlinked: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
