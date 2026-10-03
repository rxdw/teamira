# assets/premium

Empty on purpose — this whole folder is a wildcard asset directory (see
pubspec.yaml), the same way assets/onboarding/ is.

Drop a muted, loopable video in here named exactly:

    paywall_bg.mp4

...and the paywall's hero (PremiumScreen's `_Hero` /
`_PaywallVideoBackdrop`, in lib/screens/premium/premium_screen.dart)
will pick it up automatically on the next build — no code change
needed. Until then, the hero just shows its current solid accent
gradient, exactly as it always has.

A few things worth knowing before you drop one in:

- It plays silently and on a loop, filling the hero edge-to-edge
  (BoxFit.cover) — same handling as onboarding's own background video,
  so whatever aspect ratio you shoot doesn't need to match the hero's
  shape exactly.
- A soft accent-colored gradient sits over it for text legibility (see
  `_PaywallVideoBackdropState.build`) — footage that reads a little
  busy or bright on its own usually still looks calm once that scrim
  is on top, so don't over-correct for it in the edit.
- Keep it short and small — a few seconds, looped, is plenty; this
  ships inside the app bundle, not streamed.
