import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/palette.dart';
import '../theme/seenly_brightness.dart';

// ---------------------------------------------------------------------
// The same looping, muted, silently-autoplaying backdrop onboarding
// introduced (assets/onboarding/onboarding_bg.mp4 — see
// screens/onboarding/onboarding_screen.dart's _VideoBackdrop), promoted
// here so the rest of the app — not just the onboarding tour — can sit
// on top of it.
//
// Onboarding keeps its own private copy rather than importing this one:
// it's a carefully tuned, self-contained flow, and reusing its exact
// controller instance here would tie this file's lifetime to whether
// onboarding happens to be mounted. This file exists purely so every
// *other* screen shares ONE decode instead of each screen starting its
// own — see [AppBackgroundVideo] below.
// ---------------------------------------------------------------------

/// One video decode for the whole app. RootShell mounts the single
/// [AppVideoBackground] that ever exists on screen, once, underneath its
/// whole tab [IndexedStack] (see screens/shell/root_shell.dart) — no
/// other screen should mount a second one. Despite appearances,
/// [VideoPlayer] does *not* reliably support the same controller being
/// painted by two simultaneously-live widgets at once: IndexedStack keeps
/// every tab's widget tree mounted and rebuilding regardless of which
/// tab is actually showing, so a tab that also painted its own copy
/// (Diary used to) was a second live consumer of this controller on
/// every frame Diary was the active tab, not just when it happened to be
/// pushed on its own — that double-mount, not anything about the decode
/// itself, is what made the video freeze/misbehave. Diary now relies
/// entirely on RootShell's single copy, the same as every other tab.
///
/// Never disposed — this is meant to keep quietly looping for the whole
/// app session, the same "ambient, always-on" lifetime a persistent
/// audio player would have, not a per-screen resource.
class AppBackgroundVideo {
  AppBackgroundVideo._() {
    SeenlyBrightness.setVideoBackdrop(enabled.value);
  }
  static final AppBackgroundVideo instance = AppBackgroundVideo._();

  VideoPlayerController? _controller;

  /// Whether the ambient backdrop is currently shown. Toggled from the
  /// Home screen's video icon; [AppVideoBackground] listens to this and
  /// falls back to a flat tinted background (no video, no decode work)
  /// while it's false — access to Friends Activity lives on its own
  /// card now and no longer rides on this button.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  void toggle() {
    // Palette flag first: listeners of [enabled] rebuild the app and must
    // already see the matching light/dark palette.
    SeenlyBrightness.setVideoBackdrop(!enabled.value);
    enabled.value = !enabled.value;
    final existing = _controller;
    if (existing == null) return;
    if (enabled.value) {
      existing.play();
    } else {
      existing.pause();
    }
  }

  VideoPlayerController get controller {
    final existing = _controller;
    if (existing != null) return existing;
    final created = VideoPlayerController.asset('assets/onboarding/onboarding_bg.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _controller = created;
    created.initialize().then((_) => created.play());
    return created;
  }
}

/// Drops the shared backdrop behind whatever's on screen, tinted to the
/// *current* [SeenlyPalette.background] rather than onboarding's fixed
/// night colour — onboarding is one continuous dark scene built around
/// this footage; the rest of the app is a light-paper (or dark-mode, or
/// cozy) screen with its own text colours already tuned for its own
/// background. Reading the live palette here means the scrim always
/// matches whatever's actually behind the video — light cream in classic
/// light mode, near-black in dark mode — so existing text keeps the
/// contrast it already had; the video reads as a slow, faint texture
/// moving under the page rather than a wholesale re-theme.
///
/// Mount this once, as the very first child of RootShell's Stack (see
/// screens/shell/root_shell.dart) — everything else paints on top of it
/// exactly as it did on top of a flat colour before. Don't mount a second
/// one elsewhere in the tree (see [AppBackgroundVideo]'s own doc comment
/// above for why that's the one thing this widget can't tolerate).
class AppVideoBackground extends StatelessWidget {
  /// How strongly the current background colour is layered over the
  /// video. 1.0 would hide it completely; 0.0 would leave it exactly as
  /// bold as onboarding's own cut.
  ///
  /// When null (the default) the strength follows the active palette:
  /// 0.64 on dark themes, 0.68 on light ones. The footage is not dark
  /// (mean ~38% luminance, highlights ~90%), and text sitting directly on
  /// it, with no card behind, dropped to 1.4-2.4:1 contrast at the old
  /// flat 0.5 — it read as missing. These values (with the matching text
  /// tones from SeenlyPalette._forVideo) are a deliberate trade toward a
  /// more visible video: primary text stays >= ~4.1:1 against the worst
  /// 1% of pixels, secondary tones land around 3-4.6:1. Raise them if
  /// captions/metadata get hard to read over bright patches.
  final double? scrimOpacity;

  const AppVideoBackground({super.key, this.scrimOpacity});

  @override
  Widget build(BuildContext context) {
    final tint = SeenlyPalette.background;
    final scrim = scrimOpacity ?? (SeenlyBrightness.isDark ? 0.64 : 0.68);
    return ValueListenableBuilder<bool>(
      valueListenable: AppBackgroundVideo.instance.enabled,
      builder: (context, isEnabled, _) {
        if (!isEnabled) {
          // Off: plain tinted background, same colour the video would
          // otherwise sit under — no controller access, no decode.
          return ColoredBox(color: tint);
        }
        final controller = AppBackgroundVideo.instance.controller;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final video = !value.isInitialized || value.size.width <= 0
                ? ColoredBox(color: tint)
                : ColoredBox(
                    color: tint,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: value.size.width,
                        height: value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  );
            return Stack(
              fit: StackFit.expand,
              children: [
                video,
                IgnorePointer(child: ColoredBox(color: tint.withOpacity(scrim))),
              ],
            );
          },
        );
      },
    );
  }
}
