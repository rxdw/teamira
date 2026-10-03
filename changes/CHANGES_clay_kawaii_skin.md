# Clay skin rebuilt as real kawaii claymorphism

The old "clay" skin was the standard skin recoloured lavender (palette + font +
one extra drop shadow). It is replaced by an actual claymorphism design system.

## What "clay" means now
- **Anatomy of a clay surface** (`theme/clay_kit.dart`): fat squircle radius,
  tinted outer drop shadow + white bounce light, and a real **inner highlight
  (top-left) + inner shade (bottom-right)** painted by `ClayBoxDecoration`
  (Flutter's BoxShadow can't be inset, so the decoration paints it itself).
  It is inert outside the clay skin, so classic and cozy are unchanged.
- **Palette** (`theme/palette.dart`): milky peach background `#FFEFE9`, warm
  white cards, cocoa-berry ink `#5B3F4D`, bubblegum accent `#EA6B9B`, candy
  pastels for the categorical colours (mint, butter, peach, sky-lilac).
  Dark mode is "candy at bedtime" (aubergine `#2B2030`). No more neon violet.
- **Typography** (`theme/text_styles.dart`): Nunito 800/900 headings, 600+ body.
  The previous Fredoka/Quicksand pair has no Cyrillic glyphs, so in the Russian
  interface every clay heading/label was silently falling back to the platform
  font.
- **Components** (`theme/clay_kit.dart`): `ClaySurface`, `ClayButton` (squishy:
  press collapses the shadow and deepens the inner shade), `ClayChip`,
  `ClayTabBar` (dented tray + raised pill), `KawaiiFace`, `ClayBlobFace`,
  `ClayLoader` (hopping blob with a face), `ClayBackdrop` (gradient, colour
  clouds, drifting hearts/sparkles/clouds/flowers), `clayWellDecoration`
  (pressed-in text fields).
- **App chrome**: floating clay dock with a gliding bubblegum bubble
  (`widgets/seenly_bottom_nav.dart`); clay backdrop instead of the looping video
  in `RootShell`; underline tabs -> clay segmented tabs, `PillChip`,
  `PrimaryButton`, `GenreTag`, `MediaCountTile`, `SeenlyEmptyState`,
  `ThemedLoadingIndicator`, `PosterTile`, Home "ask" field and Search field.
- **Theme** (`theme/app_theme.dart`): clay branch for buttons, cards, dialogs,
  bottom sheets, chips, inputs (no outlines), snackbars, switch, slider, progress.
- **Existing cards**: every `BoxDecoration(... softShadow ...)` (112 sites) and
  every flat `paper + borderRadius` card (97 sites) now uses `ClayBoxDecoration`
  (new `SeenlyPalette.flatCardShadow` is empty outside clay).
- Onboarding skin preview and the Settings swatch updated to the new look.

## Known limits
- Pushed (non-tab) screens get the clay background colour and clay components,
  but not the drifting doodle backdrop (it lives in `RootShell` only).
- Bespoke widgets with their own hand-rolled gradients/painters (logging
  rituals, wrapped, passport, etc.) were not restyled.
- `AnimatedContainer` lerps between decorations produce a plain `BoxDecoration`
  mid-animation, so inner shading pops in when such an animation settles.
