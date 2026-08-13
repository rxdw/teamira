import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'palette.dart';

/// Turns a poster/backdrop image into a single soft background tint for
/// the title detail screen — the idea being the screen's backdrop
/// gently picks up the poster's own mood (a warm western leans amber, a
/// moody thriller leans slate) instead of always sitting on the exact
/// same flat paper color no matter what's showing.
///
/// Two things keep this from turning into a Spotify-style saturated
/// color-block behind the content, which would clash with the rest of
/// the app's "warm paper diary" look:
///
/// 1. Swatch choice — [PaletteGenerator]'s *muted* swatches are already
///    the desaturated, mid-lightness colors in an image (as opposed to
///    vibrant/dominant, which chase the most eye-catching color even if
///    that's a single neon sign in an otherwise dark frame). Preferring
///    muted first means the starting point is already closer to "wall
///    paint" than "poster ink".
/// 2. [_soften] then forces that color's lightness and saturation into
///    a narrow band matching the app's own washi-tape accents — so a
///    pitch-black poster and a blown-out white one both land as a soft,
///    tape-like tint that only differs from the next title by *hue*,
///    never by how light or how saturated it is. The screen should
///    still look like it belongs to this app first, and to this poster
///    second.
class PosterPaletteService {
  PosterPaletteService._();

  // Keyed by image URL. In-memory only (a session's worth of titles a
  // person actually opens is small, and this is a mood tint, not data —
  // nothing here is worth persisting to disk across app launches).
  static final Map<String, Color?> _cache = {};

  /// Returns a soft background tint for [imageUrl], or null if there's
  /// no image, the image fails to load, or extraction takes too long —
  /// any of which should just leave the screen on its normal flat
  /// background rather than block or throw.
  static Future<Color?> extract(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (_cache.containsKey(imageUrl)) return _cache[imageUrl];

    try {
      final generator = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        // Small target — this is one blended color, not per-pixel
        // detail, so there's nothing to gain from quantizing a
        // full-resolution poster. Keeps this fast enough to not be
        // noticeable against the rest of the detail screen's own load.
        size: const Size(80, 120),
        maximumColorCount: 12,
      ).timeout(const Duration(seconds: 5));

      final swatch = generator.mutedColor ??
          generator.lightMutedColor ??
          generator.darkMutedColor ??
          generator.dominantColor;
      final tint = swatch == null ? null : _soften(swatch.color);
      if (kDebugMode) {
        debugPrint(
          'PosterPaletteService: $imageUrl -> swatch=${swatch?.color} tint=$tint',
        );
      }
      _cache[imageUrl] = tint;
      return tint;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PosterPaletteService: extraction failed for $imageUrl -> $e');
      }
      _cache[imageUrl] = null;
      return null;
    }
  }

  /// Pulls [color] toward the app's washi-tape accent colors' lightness
  /// and saturation register, keeping only its hue as the thing that
  /// actually varies from poster to poster.
  static Color _soften(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Calibrated against the app's own washi-tape accents (tapeRose,
    // tapeSage, tapeMustard — the polaroid-corner colors) instead of
    // against the paper background's own near-white L/S. Matching the
    // paper was the original bug: paperHsl sits around L 0.92 / S 0.06,
    // so clamping the tint's lightness/saturation that close to it
    // landed the result only 1-2% off the background in every channel
    // — technically a different color, invisible in practice.
    //
    // None of the three tape samples actually fall in the cool
    // (150-300°) hue range though — they're all warm (rose/mustard) —
    // so the cool branch below was tuned by guesswork the first time,
    // and it guessed too strong: a saturated blue poster (space movies,
    // moody thrillers) was landing eye-searingly vivid across the
    // entire card instead of reading as a soft wash. Cool hues get
    // noticeably lower saturation and higher lightness than warm ones
    // here — blues/purples read as "loud" at a given S/L where an
    // amber or rose at the same numbers still reads as gentle, so they
    // need more headroom pulled back to land in the same felt register
    // as the tape accents.
    final isCool = hsl.hue > 150 && hsl.hue < 300;
    final lightness = (isCool ? 0.83 : 0.80).clamp(0.0, 1.0);
    final saturation = (isCool ? 0.24 : 0.34).clamp(0.0, 1.0);

    final softened = HSLColor.fromAHSL(1.0, hsl.hue, saturation, lightness).toColor();

    // Still blended toward paper so it reads as "paper with a wash of
    // color" rather than a flat pastel swatch dropped on top — just
    // lighter-handed than before (0.85 vs 0.7) now that the target L/S
    // is already close to the app's own tape-accent register and
    // doesn't need as much pulling back to belong.
    return Color.lerp(SeenlyPalette.background, softened, 0.85)!;
  }
}
