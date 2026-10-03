import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/diary_entry.dart';
import '../models/profile_stats.dart';
import 'app_translations.dart';
import 'locale_service.dart';

/// Builds the two premium PDF exports reachable from
/// [KeepsakeExportScreen]'s Diary/Wrapped tabs:
///
///  - [build] — the "diary keepsake": a plum, foil-stamped journal cover,
///    an "at a glance" opening spread, then every logged evening month by
///    month on dot-grid paper — poster polaroids held by washi tape,
///    painted hearts, handwritten notes — and a matching back cover.
///  - [buildWrapped] — a period's [WrappedSummary] as a deck of cinema
///    *tickets* on the same night sky the on-screen Wrapped uses (see
///    `_WrappedNightBackdrop` in wrapped_screen.dart): one chapter per
///    ticket, perforated stub with a page number and barcode, closed by a
///    zig-zag paper receipt.
///
/// What changed vs. the first version, and why it looked flat:
///  - The old "full-bleed" story pages were a colored Container *inside*
///    the page margins, so every one had a white frame around it. All
///    backgrounds are now painted through `PageTheme.buildBackground`
///    inside a `FullPage(ignoreMargins: true)` — a real edge-to-edge fill.
///  - Fonts are the app's own three (Unbounded / Comfortaa / Caveat),
///    bundled in assets/pdf_fonts as static, Latin+Cyrillic subsets,
///    instead of Noto fetched over the network at export time. That is
///    both on-brand and makes the export work offline (posters are the
///    only network dependency left, and they already degrade gracefully).
///  - Hearts are *painted* now. Noto Sans has no U+2665/U+2661 glyphs, so
///    the old "♥ ♡" rating rows were probably rendering as blanks. Ratings
///    are also the app's real 1–10 scale (one heart per point) instead of
///    being rounded down to five.
///  - Shapes, rings, sparkles, tape, tilted polaroids, ticket notches and
///    the receipt teeth are drawn with `CustomPaint` / `Transform.rotate`
///    — both checked against the `pdf` package source (3.13) rather than
///    assumed. No color alpha is used anywhere (the package ignores it on
///    fills); every "soft" tone is pre-blended with [_mix].
class KeepsakePdfService {
  const KeepsakePdfService._();

  // The rebrand is mid-flight in the app (see the "tanè" strings in
  // app_translations.dart); this PDF used to say TEAMIRA on the cover and
  // "tanè" in the footer. One constant so it can't drift again.
  static const _brand = 'tanè';

  // ---------------------------------------------------------------------
  // Palette — light tokens mirror SeenlyPalette (theme/palette.dart); the
  // night / plum / foil trio is new and only used for covers, the Wrapped
  // sky and other "evening" surfaces. `_night` is wrapped_screen.dart's
  // own `_wrappedNightColor`.
  // ---------------------------------------------------------------------
  static const _background = PdfColor.fromInt(0xFFF5EFE4);
  static const _paper = PdfColor.fromInt(0xFFFFFDF8);
  static const _polaroid = PdfColor.fromInt(0xFFFFFDF7);
  static const _cork = PdfColor.fromInt(0xFFE9DBBF);
  static const _ink = PdfColor.fromInt(0xFF4A3F38);
  static const _inkMuted = PdfColor.fromInt(0xFF8A7A68);
  static const _inkFaint = PdfColor.fromInt(0xFFA8967F);
  static const _border = PdfColor.fromInt(0xFFE4D9C4);
  static const _dot = PdfColor.fromInt(0xFFDCCDB4);
  static const _accent = PdfColor.fromInt(0xFF7D5A6B);
  static const _cream = PdfColor.fromInt(0xFFFBF3E6);
  static const _sage = PdfColor.fromInt(0xFF8FA382);
  static const _mustard = PdfColor.fromInt(0xFFC99A4C);
  static const _coral = PdfColor.fromInt(0xFFD85A30);
  static const _pink = PdfColor.fromInt(0xFFD4537E);
  static const _periwinkle = PdfColor.fromInt(0xFF7F77DD);
  static const _clay = PdfColor.fromInt(0xFFB6704A);
  static const _night = PdfColor.fromInt(0xFF241A22);
  static const _plum = PdfColor.fromInt(0xFF3B2733);
  static const _foil = PdfColor.fromInt(0xFFDDB877);

  static const _wrappedRotation = [_accent, _coral, _sage, _mustard, _periwinkle, _clay];

  static PdfColor _mediaColor(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return _coral;
      case 'series':
        return _sage;
      case 'game':
        return _periwinkle;
      case 'anime':
        return _mustard;
      case 'book':
        return _pink;
      case 'manga':
        return _clay;
      default:
        return _accent;
    }
  }

  static PdfColor _mix(PdfColor a, PdfColor b, double t) => PdfColor(
        a.red + (b.red - a.red) * t,
        a.green + (b.green - a.green) * t,
        a.blue + (b.blue - a.blue) * t,
      );

  static bool _isLight(PdfColor c) => (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) > 0.58;

  /// Readable foreground for text sitting on [bg].
  static PdfColor _onTone(PdfColor bg) => _isLight(bg) ? _ink : _cream;

  /// Warmer with a higher score, same idea as SeenlyPalette.ratingColor.
  static PdfColor _ratingColor(int r) => _mix(_accent, _pink, ((r - 1) / 9).clamp(0.0, 1.0).toDouble());

  // ---------------------------------------------------------------------
  // Copy helpers
  // ---------------------------------------------------------------------

  static String _l(String ru, String en) => LocaleService.appIsRussian ? ru : en;

  static const _monthNamesRu = [
    '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];
  static const _monthNamesEn = [
    '', 'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
  ];
  static const _monthShortRu = [
    '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  static const _monthShortEn = [
    '', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  static const _weekdayShortRu = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  static const _weekdayShortEn = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'];
  static const _weekdayFullRu = [
    'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье',
  ];
  static const _weekdayFullEn = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  static String _monthName(int m) => (LocaleService.appIsRussian ? _monthNamesRu : _monthNamesEn)[m];
  static String _monthShort(int m) => (LocaleService.appIsRussian ? _monthShortRu : _monthShortEn)[m];
  static String _monthYear(int month, int year) => '${_monthName(month)} $year';
  static String _weekdayShort(DateTime d) =>
      (LocaleService.appIsRussian ? _weekdayShortRu : _weekdayShortEn)[d.weekday - 1];

  static String _pluralRu(int n, String one, String few, String many) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return many;
    switch (n % 10) {
      case 1:
        return one;
      case 2:
      case 3:
      case 4:
        return few;
      default:
        return many;
    }
  }

  static String _eveningsLabel(int n) => LocaleService.appIsRussian
      ? '$n ${_pluralRu(n, 'вечер', 'вечера', 'вечеров')}'
      : '$n ${n == 1 ? 'evening' : 'evenings'}';

  static String _daysLabel(int n) {
    if (LocaleService.appIsRussian) return '$n ${_pluralRu(n, 'день', 'дня', 'дней')}';
    return '$n ${n == 1 ? 'day' : 'days'}';
  }

  static String _hoursLabel(double totalHours) {
    final totalMinutes = (totalHours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (LocaleService.appIsRussian) return '$h ч ${m.toString().padLeft(2, '0')} мин';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

  static String _spaced(String s) => s.toUpperCase().split('').join(' ');

  static String _thanksLine(String scope) {
    if (LocaleService.appIsRussian) {
      return scope == 'month'
          ? 'спасибо за этот месяц'
          : scope == 'custom'
              ? 'спасибо за эти дни'
              : 'спасибо за этот год';
    }
    return scope == 'month'
        ? 'thanks for this month'
        : scope == 'custom'
            ? 'thanks for these days'
            : 'thanks for this year';
  }

  // ---------------------------------------------------------------------
  // Fonts (bundled — see assets/pdf_fonts/README.md)
  // ---------------------------------------------------------------------

  static Future<_Fonts> _loadFonts() async {
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/pdf_fonts/$name'));
    return _Fonts(
      display: await f('Unbounded-Bold.ttf'),
      black: await f('Unbounded-Black.ttf'),
      body: await f('Comfortaa-Regular.ttf'),
      bodyBold: await f('Comfortaa-Bold.ttf'),
      hand: await f('Caveat-Regular.ttf'),
      handBold: await f('Caveat-Bold.ttf'),
    );
  }

  static pw.TextStyle _t(pw.Font font, double size, PdfColor color, {double? ls, double? lh}) =>
      pw.TextStyle(font: font, fontSize: size, color: color, letterSpacing: ls, lineSpacing: lh);

  // ---------------------------------------------------------------------
  // Network / asset images — unchanged behavior: batched, capped, never
  // allowed to fail the export.
  // ---------------------------------------------------------------------

  static Future<Map<String, pw.MemoryImage>> _fetchPosters(
    Iterable<String?> urls, {
    int maxImages = 220,
    int batchSize = 8,
  }) async {
    final unique = <String>{
      for (final u in urls)
        if (u != null && u.trim().isNotEmpty) u,
    }.take(maxImages).toList();

    final out = <String, pw.MemoryImage>{};
    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.sublist(i, (i + batchSize).clamp(0, unique.length));
      final results = await Future.wait(batch.map(_fetchOnePoster));
      for (var j = 0; j < batch.length; j++) {
        final img = results[j];
        if (img != null) out[batch[j]] = img;
      }
    }
    return out;
  }

  static Future<pw.MemoryImage?> _fetchOnePoster(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      return pw.MemoryImage(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<pw.MemoryImage?> _loadMascot() async {
    try {
      final data = await rootBundle.load('assets/mascot/bunnies_coViewing.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  // =====================================================================
  // Low-level painting
  // =====================================================================

  static const double _pageW = 595.28;
  static const double _pageH = 841.89;

  static void _rr(PdfGraphics c, double x, double y, double w, double h, double r) =>
      c.drawRRect(x, y, w, h, r, r);

  static void _fillRect(PdfGraphics c, PdfColor col, double x, double y, double w, double h) {
    c.setFillColor(col);
    c.drawRect(x, y, w, h);
    c.fillPath();
  }

  static void _fillCircle(PdfGraphics c, PdfColor col, double cx, double cy, double r) {
    c.setFillColor(col);
    c.drawEllipse(cx, cy, r, r);
    c.fillPath();
  }

  /// Four-point sparkle, concave sides.
  static void _sparkle(PdfGraphics c, PdfColor col, double cx, double cy, double r) {
    final k = r * 0.14;
    c.setFillColor(col);
    c.moveTo(cx, cy + r);
    c.curveTo(cx + k, cy + k, cx + k, cy + k, cx + r, cy);
    c.curveTo(cx + k, cy - k, cx + k, cy - k, cx, cy - r);
    c.curveTo(cx - k, cy - k, cx - k, cy - k, cx - r, cy);
    c.curveTo(cx - k, cy + k, cx - k, cy + k, cx, cy + r);
    c.fillPath();
  }

  /// A soft glow faked with concentric opaque circles pre-blended toward
  /// [tint] on a flat [bg] — same look as a low-alpha radial, without
  /// depending on alpha support.
  static void _glow(PdfGraphics c, double cx, double cy, double r, PdfColor tint, PdfColor bg,
      {double strength = 0.035}) {
    const steps = 8;
    for (var i = 0; i < steps; i++) {
      final radius = r * (1 - i / steps);
      _fillCircle(c, _mix(bg, tint, strength * (i + 1)), cx, cy, radius);
    }
  }

  static void _stars(PdfGraphics c, PdfPoint s, int seed, int count, PdfColor bg,
      {double top = 0, double bottom = 0}) {
    final rnd = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * s.x;
      final y = bottom + rnd.nextDouble() * (s.y - top - bottom);
      final bright = 0.3 + 0.65 * rnd.nextDouble();
      final r = 0.5 + rnd.nextDouble() * 1.2;
      if (i % 9 == 0) {
        _sparkle(c, _mix(bg, _foil, 0.4 + 0.5 * rnd.nextDouble()), x, y, r * 4.2);
      } else {
        _fillCircle(c, _mix(bg, _cream, bright), x, y, r);
      }
    }
  }

  /// Heart outline (Material "favorite" glyph) with its bottom-left at
  /// (x, y), [size] wide. Drawn by hand because the PDF fonts in play have
  /// no heart codepoints.
  static void _heartPath(PdfGraphics c, double x, double y, double size) {
    final k = size / 20.0;
    double px(double v) => x + (v - 2) * k;
    double py(double v) => y + (21.35 - v) * k;
    c.moveTo(px(12), py(21.35));
    c.lineTo(px(10.55), py(20.03));
    c.curveTo(px(5.4), py(15.36), px(2), py(12.28), px(2), py(8.5));
    c.curveTo(px(2), py(5.42), px(4.42), py(3), px(7.5), py(3));
    c.curveTo(px(9.24), py(3), px(10.91), py(3.81), px(12), py(5.09));
    c.curveTo(px(13.09), py(3.81), px(14.76), py(3), px(16.5), py(3));
    c.curveTo(px(19.58), py(3), px(22), py(5.42), px(22), py(8.5));
    c.curveTo(px(22), py(12.28), px(18.6), py(15.36), px(13.45), py(20.04));
    c.lineTo(px(12), py(21.35));
  }

  /// The app's real 1–10 scale: one heart per point (see HeartRating).
  static pw.Widget _hearts(int? rating,
      {double size = 7.5, double gap = 1.5, PdfColor? fill, PdfColor empty = _dot}) {
    final r = (rating ?? 0).clamp(0, 10).toInt();
    final col = fill ?? _ratingColor(r);
    return pw.CustomPaint(
      size: PdfPoint(10 * (size + gap) - gap, size),
      painter: (c, s) {
        for (var i = 0; i < 10; i++) {
          _heartPath(c, i * (size + gap), 0, size);
          if (i < r) {
            c.setFillColor(col);
            c.fillPath();
          } else {
            c.setStrokeColor(empty);
            c.setLineWidth(0.7);
            c.strokePath();
          }
        }
      },
    );
  }

  static pw.Widget _singleHeart(double size, PdfColor color) => pw.CustomPaint(
        size: PdfPoint(size, size),
        painter: (c, s) {
          _heartPath(c, 0, 0, size);
          c.setFillColor(color);
          c.fillPath();
        },
      );

  static pw.Widget _sparkleWidget(double r, PdfColor color) => pw.CustomPaint(
        size: PdfPoint(r * 2, r * 2),
        painter: (c, s) => _sparkle(c, color, r, r, r),
      );

  /// Thin foil rule with a little sparkle in the middle.
  static pw.Widget _ornament(double width, PdfColor color) => pw.CustomPaint(
        size: PdfPoint(width, 12),
        painter: (c, s) {
          c.setStrokeColor(color);
          c.setLineWidth(0.9);
          c.moveTo(0, 6);
          c.lineTo(width / 2 - 14, 6);
          c.strokePath();
          c.moveTo(width / 2 + 14, 6);
          c.lineTo(width, 6);
          c.strokePath();
          _sparkle(c, color, width / 2, 6, 6);
        },
      );

  static pw.Widget _dashedRule(double width, PdfColor color, {double dash = 4, double gap = 3}) => pw.CustomPaint(
        size: PdfPoint(width, 2),
        painter: (c, s) {
          c.setStrokeColor(color);
          c.setLineWidth(1);
          c.setLineDashPattern([dash, gap]);
          c.moveTo(0, 1);
          c.lineTo(width, 1);
          c.strokePath();
        },
      );

  static pw.Widget _barcode(double w, double h, PdfColor color, int seed) => pw.CustomPaint(
        size: PdfPoint(w, h),
        painter: (c, s) {
          final rnd = math.Random(seed);
          var x = 0.0;
          c.setFillColor(color);
          while (x < w) {
            final bw = 1.0 + rnd.nextInt(3);
            if (rnd.nextBool() && x + bw <= w) {
              c.drawRect(x, 0, bw, h);
              c.fillPath();
            }
            x += bw + 1.3;
          }
        },
      );

  // ---------------------------------------------------------------------
  // Backgrounds (used through PageTheme.buildBackground so they are real
  // edge-to-edge fills, margins notwithstanding)
  // ---------------------------------------------------------------------

  static pw.Widget _fullPage(void Function(PdfGraphics c, PdfPoint s) painter) => pw.FullPage(
        ignoreMargins: true,
        child: pw.CustomPaint(size: const PdfPoint(_pageW, _pageH), painter: painter),
      );

  /// Warm paper with a bullet-journal dot grid. The dots are zero-length
  /// dashes with round caps — 45 strokes a page instead of ~1,500 circles,
  /// so a 200-entry diary doesn't balloon.
  static void _paintPaper(PdfGraphics c, PdfPoint s) {
    _fillRect(c, _background, 0, 0, s.x, s.y);
    c.setStrokeColor(_dot);
    c.setLineWidth(1.1);
    c.setLineCap(PdfLineCap.round);
    c.setLineDashPattern([0.01, 17.99]);
    for (var y = 30.0; y < s.y - 20; y += 18) {
      c.moveTo(30, y);
      c.lineTo(s.x - 30, y);
      c.strokePath();
    }
    c.setLineDashPattern();
  }

  static void _paintCover(PdfGraphics c, PdfPoint s, int seed) {
    _fillRect(c, _plum, 0, 0, s.x, s.y);
    _glow(c, s.x * 0.12, s.y * 0.88, 300, _accent, _plum);
    _glow(c, s.x * 0.95, s.y * 0.1, 320, _clay, _plum, strength: 0.03);
    _stars(c, s, seed, 90, _plum, top: 60, bottom: 60);

    c.setStrokeColor(_foil);
    c.setLineWidth(1.6);
    _rr(c, 26, 26, s.x - 52, s.y - 52, 18);
    c.strokePath();
    c.setLineWidth(0.8);
    c.setLineDashPattern([3, 3]);
    _rr(c, 35, 35, s.x - 70, s.y - 70, 12);
    c.strokePath();
    c.setLineDashPattern();

    _sparkle(c, _foil, 52, 52, 8);
    _sparkle(c, _foil, s.x - 52, 52, 8);
    _sparkle(c, _foil, 52, s.y - 52, 8);
    _sparkle(c, _foil, s.x - 52, s.y - 52, 8);
  }

  /// Night sky for Wrapped pages. [ticket] is the card rect (x, y, w, h,
  /// y-up) whose stacked shadow gets painted here — a widget inside a
  /// Stack can't paint outside its own bounds, the page background can.
  static void _paintNight(PdfGraphics c, PdfPoint s, int seed, List<double>? ticket) {
    _fillRect(c, _night, 0, 0, s.x, s.y);
    _glow(c, s.x * 0.05, s.y * 0.95, 260, _mustard, _night, strength: 0.022);
    _glow(c, s.x * 0.98, s.y * 0.9, 240, _periwinkle, _night, strength: 0.028);
    _glow(c, s.x * 0.1, s.y * 0.05, 240, _pink, _night, strength: 0.026);
    _glow(c, s.x * 0.95, s.y * 0.06, 260, _coral, _night, strength: 0.022);
    _stars(c, s, seed, 70, _night);
    if (ticket != null) {
      for (var i = 5; i >= 1; i--) {
        c.setFillColor(_mix(_night, PdfColors.black, 0.13 * (6 - i)));
        _rr(c, ticket[0] - i * 0.9, ticket[1] - i * 3.6, ticket[2] + i * 1.8, ticket[3], 28);
        c.fillPath();
      }
    }
  }

  // =====================================================================
  // Shared widgets
  // =====================================================================

  static pw.Widget _poster({
    required Map<String, pw.MemoryImage> posters,
    required String? url,
    required String title,
    required PdfColor color,
    required double width,
    required double height,
    required _Fonts fonts,
    double radius = 3,
  }) {
    final img = (url != null) ? posters[url] : null;
    if (img != null) {
      return pw.ClipRRect(
        horizontalRadius: radius,
        verticalRadius: radius,
        child: pw.Image(img, width: width, height: height, fit: pw.BoxFit.cover),
      );
    }
    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(radius)),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title.trim().isNotEmpty ? title.trim()[0].toUpperCase() : '•',
        style: _t(fonts.black, height * 0.34, _mix(color, _cream, 0.8)),
      ),
    );
  }

  /// A photo-print polaroid held by a strip of washi tape, tilted by
  /// [tilt] radians. `Transform.rotate` doesn't change layout size, so
  /// callers leave a few points of slack around it.
  static pw.Widget _polaroidWidget({
    required Map<String, pw.MemoryImage> posters,
    required String? url,
    required String title,
    required PdfColor color,
    required double width,
    required double height,
    required _Fonts fonts,
    double tilt = 0,
    PdfColor tape = _mustard,
    String? caption,
    double border = 4,
  }) {
    final frameW = width + border * 2;
    final bottom = caption != null ? border * 4.6 : border * 3;
    return pw.Transform.rotate(
      angle: tilt,
      child: pw.Stack(
        overflow: pw.Overflow.visible,
        children: [
          pw.Container(
            padding: pw.EdgeInsets.fromLTRB(border, border, border, bottom),
            decoration: pw.BoxDecoration(
              color: _polaroid,
              border: pw.Border.all(color: _border, width: 0.6),
            ),
            child: _poster(
              posters: posters,
              url: url,
              title: title,
              color: color,
              width: width,
              height: height,
              fonts: fonts,
              radius: 1.5,
            ),
          ),
          if (caption != null)
            pw.Positioned(
              left: 2,
              right: 2,
              bottom: 3,
              child: pw.Center(
                child: pw.Text(
                  caption,
                  maxLines: 1,
                  style: _t(fonts.handBold, math.max(9.0, border * 2.6), _inkMuted),
                ),
              ),
            ),
          pw.Positioned(
            top: -5,
            left: frameW / 2 - 16,
            child: pw.Transform.rotate(
              angle: tilt >= 0 ? -0.14 : 0.14,
              child: pw.Container(
                width: 32,
                height: 10,
                decoration: pw.BoxDecoration(
                  color: _mix(tape, _paper, 0.38),
                  border: pw.Border.all(color: _mix(tape, _paper, 0.15), width: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pill(String text, PdfColor bg, _Fonts fonts, {double size = 6.8}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.2),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Text(text.toUpperCase(), style: _t(fonts.bodyBold, size, _onTone(bg), ls: 0.6)),
      );

  static pw.Widget _fit(pw.Widget child, {pw.Alignment alignment = pw.Alignment.centerLeft}) =>
      pw.FittedBox(fit: pw.BoxFit.scaleDown, alignment: alignment, child: child);

  // =====================================================================
  // DIARY KEEPSAKE
  // =====================================================================

  static Future<Uint8List> build({
    required List<DiaryEntry> entries,
    required String personName,
  }) async {
    final fonts = await _loadFonts();
    final mascot = await _loadMascot();
    final sorted = [...entries]..sort((a, b) => a.watchedAt.compareTo(b.watchedAt));
    final posters = await _fetchPosters(sorted.map((e) => e.posterUrl));

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.body, bold: fonts.bodyBold),
    );

    doc.addPage(_coverPage(
      personName: personName,
      count: sorted.length,
      first: sorted.isEmpty ? null : sorted.first.watchedAt,
      last: sorted.isEmpty ? null : sorted.last.watchedAt,
      fonts: fonts,
      mascot: mascot,
    ));

    if (sorted.isNotEmpty) {
      doc.addPage(_glancePage(entries: sorted, fonts: fonts, posters: posters));
      doc.addPage(_entriesMultiPage(entries: sorted, fonts: fonts, posters: posters));
    }

    doc.addPage(_closingPage(
      fonts: fonts,
      mascot: mascot,
      backCover: true,
      line: _l('и это ещё не конец', 'and this isn\'t the end'),
    ));

    return doc.save();
  }

  static pw.Widget _mascotRing(pw.MemoryImage? mascot, double size, PdfColor ring) {
    final inner = pw.ClipOval(
      child: pw.SizedBox(
        width: size,
        height: size,
        child: mascot != null
            ? pw.Image(mascot, width: size, height: size, fit: pw.BoxFit.cover)
            : pw.Container(color: _mustard),
      ),
    );
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: ring, width: 1.6)),
      child: inner,
    );
  }

  static pw.Page _coverPage({
    required String personName,
    required int count,
    required DateTime? first,
    required DateTime? last,
    required _Fonts fonts,
    required pw.MemoryImage? mascot,
  }) {
    final rangeLabel = (first != null && last != null)
        ? '${_monthYear(first.month, first.year)}  —  ${_monthYear(last.month, last.year)}'
        : null;

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage((c, s) => _paintCover(c, s, 3)),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(_spaced(_brand), style: _t(fonts.bodyBold, 11, _foil, ls: 3)),
            pw.SizedBox(height: 26),
            _mascotRing(mascot, 96, _foil),
            pw.SizedBox(height: 34),
            pw.Text(_l('твой дневник', 'your diary'), style: _t(fonts.black, 36, _cream)),
            pw.SizedBox(height: 14),
            _ornament(210, _foil),
            pw.SizedBox(height: 30),
            if (personName.isNotEmpty)
              pw.Container(
                width: 250,
                padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: pw.BoxDecoration(
                  color: _cream,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _foil, width: 1.6),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(_l('этот дневник принадлежит', 'this diary belongs to').toUpperCase(),
                        style: _t(fonts.bodyBold, 6.6, _inkMuted, ls: 1.4)),
                    pw.SizedBox(height: 5),
                    pw.Text(personName, style: _t(fonts.handBold, 30, _accent)),
                  ],
                ),
              ),
            pw.SizedBox(height: 46),
            pw.Text('$count', style: _t(fonts.black, 54, _foil)),
            pw.SizedBox(height: 4),
            pw.Text(
              count == 0
                  ? _l('пока пусто — но это только начало', 'empty for now — just the beginning')
                  : _l(_pluralRu(count, 'вечер сохранён', 'вечера сохранено', 'вечеров сохранено'),
                      count == 1 ? 'evening kept' : 'evenings kept'),
              style: _t(fonts.body, 11, _cream),
            ),
            if (rangeLabel != null) ...[
              pw.SizedBox(height: 10),
              pw.Text(rangeLabel, style: _t(fonts.handBold, 19, _foil)),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Opening spread -------------------------------------------------

  static pw.Page _glancePage({
    required List<DiaryEntry> entries,
    required _Fonts fonts,
    required Map<String, pw.MemoryImage> posters,
  }) {
    final byType = <String, int>{};
    final days = <String>{};
    final months = <String, int>{};
    final monthMeta = <String, List<int>>{};
    var ratedCount = 0;
    var ratedSum = 0;
    for (final e in entries) {
      byType[e.mediaType] = (byType[e.mediaType] ?? 0) + 1;
      days.add('${e.watchedAt.year}-${e.watchedAt.month}-${e.watchedAt.day}');
      final key = '${e.watchedAt.year}-${e.watchedAt.month}';
      months[key] = (months[key] ?? 0) + 1;
      monthMeta[key] = [e.watchedAt.month, e.watchedAt.year];
      final r = e.rating;
      if (r != null) {
        ratedCount++;
        ratedSum += r;
      }
    }
    final typeList = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final avg = ratedCount == 0 ? null : ratedSum / ratedCount;

    final favorites = entries.where((e) => e.rating != null).toList()
      ..sort((a, b) {
        final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
        return byRating != 0 ? byRating : b.watchedAt.compareTo(a.watchedAt);
      });
    final shelf = favorites.take(4).toList();

    const barW = _pageW - 68;

    pw.Widget tile(String value, String label, PdfColor color) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: pw.BoxDecoration(
              color: _paper,
              borderRadius: pw.BorderRadius.circular(14),
              border: pw.Border.all(color: _border, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 22,
                  height: 4,
                  decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2)),
                ),
                pw.SizedBox(height: 10),
                _fit(pw.Text(value, style: _t(fonts.black, 26, _ink))),
                pw.SizedBox(height: 4),
                pw.Text(label, style: _t(fonts.body, 8.5, _inkMuted)),
              ],
            ),
          ),
        );

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 46, 34, 40),
        buildBackground: (context) => _fullPage(_paintPaper),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_l('коротко', 'in short'), style: _t(fonts.black, 26, _ink)),
              pw.SizedBox(width: 10),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(_l('о твоих вечерах', 'about your evenings'), style: _t(fonts.handBold, 24, _accent)),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            children: [
              tile('${entries.length}', _l('вечеров в дневнике', 'evenings in the diary'), _accent),
              pw.SizedBox(width: 10),
              tile('${days.length}', _l('дней с записями', 'days with entries'), _sage),
              pw.SizedBox(width: 10),
              tile(avg == null ? '—' : avg.toStringAsFixed(1), _l('средняя оценка из 10', 'average rating of 10'), _pink),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(_l('из чего сделан дневник', 'what the diary is made of').toUpperCase(),
              style: _t(fonts.bodyBold, 8, _inkFaint, ls: 1.6)),
          pw.SizedBox(height: 10),
          pw.CustomPaint(
            size: const PdfPoint(barW, 16),
            painter: (c, s) {
              c.saveContext();
              _rr(c, 0, 0, s.x, s.y, 8);
              c.clipPath();
              var x = 0.0;
              for (final t in typeList) {
                final w = s.x * t.value / entries.length;
                _fillRect(c, _mediaColor(t.key), x, 0, w, s.y);
                x += w;
              }
              c.restoreContext();
            },
          ),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final t in typeList)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(color: _mediaColor(t.key), shape: pw.BoxShape.circle),
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text('${mediaTypeLabel(t.key)} · ${t.value}', style: _t(fonts.body, 9, _ink)),
                  ],
                ),
            ],
          ),
          if (shelf.isNotEmpty) ...[
            pw.SizedBox(height: 30),
            pw.Text(_l('самое любимое', 'closest to your heart').toUpperCase(),
                style: _t(fonts.bodyBold, 8, _inkFaint, ls: 1.6)),
            pw.SizedBox(height: 22),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < shelf.length; i++)
                  pw.Column(
                    children: [
                      _polaroidWidget(
                        posters: posters,
                        url: shelf[i].posterUrl,
                        title: shelf[i].displayTitle,
                        color: _mediaColor(shelf[i].mediaType),
                        width: 92,
                        height: 130,
                        fonts: fonts,
                        tilt: i.isEven ? 0.045 : -0.045,
                        tape: _wrappedRotation[i % _wrappedRotation.length],
                      ),
                      pw.SizedBox(height: 9),
                      _hearts(shelf[i].rating, size: 6.2, gap: 1),
                    ],
                  ),
              ],
            ),
          ],
          pw.SizedBox(height: 30),
          pw.Text(_l('по месяцам', 'month by month').toUpperCase(),
              style: _t(fonts.bodyBold, 8, _inkFaint, ls: 1.6)),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in months.keys.take(30))
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(9, 4, 5, 4),
                  decoration: pw.BoxDecoration(
                    color: _paper,
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: _border, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('${_monthShort(monthMeta[k]![0])} ${monthMeta[k]![1] % 100}',
                          style: _t(fonts.bodyBold, 8.5, _ink)),
                      pw.SizedBox(width: 6),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: pw.BoxDecoration(color: _cork, borderRadius: pw.BorderRadius.circular(8)),
                        child: pw.Text('${months[k]}', style: _t(fonts.bodyBold, 8, _accent)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Entries --------------------------------------------------------

  static bool _isFeature(DiaryEntry e) =>
      (e.note?.trim().isNotEmpty ?? false) || ((e.rating ?? 0) >= 9);

  static const double _contentW = _pageW - 68; // 527.28
  static const double _gap = 10;
  static const double _halfW = (_contentW - _gap) / 2;

  static pw.MultiPage _entriesMultiPage({
    required List<DiaryEntry> entries,
    required _Fonts fonts,
    required Map<String, pw.MemoryImage> posters,
  }) {
    final months = <String, List<DiaryEntry>>{};
    final monthMeta = <String, List<int>>{};
    for (final e in entries) {
      final key = '${e.watchedAt.year}-${e.watchedAt.month}';
      months.putIfAbsent(key, () => []).add(e);
      monthMeta[key] = [e.watchedAt.month, e.watchedAt.year];
    }

    final children = <pw.Widget>[];
    for (final key in months.keys) {
      final rows = _entryRows(months[key]!, fonts, posters);
      final header = _monthHeader(monthMeta[key]![0], monthMeta[key]![1], months[key]!, fonts);
      // Header + first row travel together so a month title is never
      // stranded at the bottom of a page.
      children.add(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [header, rows.first],
      ));
      children.addAll(rows.skip(1));
    }

    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 44, 34, 46),
        buildBackground: (context) => _fullPage(_paintPaper),
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(children: [
              _singleHeart(7, _accent),
              pw.SizedBox(width: 5),
              pw.Text(_brand, style: _t(fonts.bodyBold, 8, _inkFaint)),
            ]),
            pw.Text('${context.pageNumber}', style: _t(fonts.handBold, 15, _inkMuted)),
          ],
        ),
      ),
      build: (context) => children,
    );
  }

  static pw.Widget _monthHeader(int month, int year, List<DiaryEntry> list, _Fonts fonts) {
    final dots = list.take(46).toList();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_monthName(month), style: _t(fonts.black, 30, _ink)),
              pw.SizedBox(width: 10),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text('$year', style: _t(fonts.handBold, 26, _accent)),
              ),
              pw.Spacer(),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(10)),
                  child: pw.Text(_eveningsLabel(list.length), style: _t(fonts.bodyBold, 8, _cream)),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          // The month as a strip of colored beads, one per evening.
          pw.CustomPaint(
            size: const PdfPoint(_contentW, 8),
            painter: (c, s) {
              c.setStrokeColor(_border);
              c.setLineWidth(1);
              c.moveTo(0, 4);
              c.lineTo(s.x, 4);
              c.strokePath();
              var x = 0.0;
              for (final e in dots) {
                _fillCircle(c, _mediaColor(e.mediaType), x + 4, 4, 3.6);
                x += 11;
              }
            },
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _entryRows(List<DiaryEntry> es, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    final rows = <pw.Widget>[];
    var i = 0;
    while (i < es.length) {
      final e = es[i];
      pw.Widget row;
      if (_isFeature(e)) {
        row = _featureCard(e, i, fonts, posters);
        i++;
      } else if (i + 1 < es.length && !_isFeature(es[i + 1])) {
        row = pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _compactCard(e, _halfW, i, fonts, posters),
            pw.SizedBox(width: _gap),
            _compactCard(es[i + 1], _halfW, i + 1, fonts, posters),
          ],
        );
        i += 2;
      } else {
        row = _compactCard(e, _contentW, i, fonts, posters);
        i++;
      }
      rows.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 12), child: row));
    }
    return rows;
  }

  /// Folded top-right corner, painted over the card as a foreground.
  static pw.Widget _dogEar(pw.Widget card, PdfColor color, {double fold = 15}) => pw.CustomPaint(
        foregroundPainter: (c, s) {
          final w = s.x;
          final h = s.y;
          c.setFillColor(_background);
          c.moveTo(w - fold, h);
          c.lineTo(w, h);
          c.lineTo(w, h - fold);
          c.fillPath();
          c.setFillColor(_mix(_paper, color, 0.32));
          c.moveTo(w - fold, h);
          c.lineTo(w - fold, h - fold);
          c.lineTo(w, h - fold);
          c.fillPath();
          c.setStrokeColor(_border);
          c.setLineWidth(0.8);
          c.moveTo(w - fold, h);
          c.lineTo(w, h - fold);
          c.strokePath();
        },
        child: card,
      );

  static pw.Widget _dayBlock(DiaryEntry e, PdfColor color, _Fonts fonts) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(e.watchedAt.day.toString().padLeft(2, '0'), style: _t(fonts.black, 19, color)),
          pw.Text(_weekdayShort(e.watchedAt).toUpperCase(), style: _t(fonts.bodyBold, 6.8, _inkFaint, ls: 1)),
        ],
      );

  static String? _episodeLabel(DiaryEntry e) =>
      e.isEpisodeEntry ? _l('сезон ${e.season} · серия ${e.episode}', 'season ${e.season} · ep ${e.episode}') : null;

  static pw.Widget _compactCard(
      DiaryEntry e, double width, int index, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    final color = _mediaColor(e.mediaType);
    final ep = _episodeLabel(e);
    return _dogEar(
      pw.Container(
        width: width,
        height: 96,
        padding: const pw.EdgeInsets.fromLTRB(11, 10, 12, 10),
        decoration: pw.BoxDecoration(
          color: _paper,
          borderRadius: pw.BorderRadius.circular(14),
          border: pw.Border.all(color: _border, width: 0.8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3, left: 2),
              child: _polaroidWidget(
                posters: posters,
                url: e.posterUrl,
                title: e.displayTitle,
                color: color,
                width: 36,
                height: 52,
                fonts: fonts,
                border: 2.4,
                tilt: index.isEven ? -0.05 : 0.05,
                tape: color,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      _pill(mediaTypeLabel(e.mediaType), color, fonts),
                      if (e.isRewatch) ...[
                        pw.SizedBox(width: 5),
                        pw.Text(_l('пересмотр', 'rewatch'), style: _t(fonts.hand, 11, _inkMuted)),
                      ],
                      pw.Spacer(),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 12),
                        child: pw.Text(
                          '${_weekdayShort(e.watchedAt)} ${e.watchedAt.day.toString().padLeft(2, '0')}',
                          style: _t(fonts.bodyBold, 8, _inkFaint),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(_clip(e.displayTitle, 44), maxLines: 2, style: _t(fonts.display, 9.2, _ink, lh: 1.5)),
                  pw.Spacer(),
                  if (ep != null) pw.Text(ep, style: _t(fonts.body, 7.5, _inkMuted)),
                  if (ep != null) pw.SizedBox(height: 3),
                  if (e.rating != null)
                    _hearts(e.rating, size: 6.6, gap: 1.2)
                  else
                    pw.Text(_l('без оценки', 'not rated'), style: _t(fonts.hand, 11, _inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
      color,
    );
  }

  static pw.Widget _featureCard(DiaryEntry e, int index, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    final color = _mediaColor(e.mediaType);
    final note = (e.note ?? '').trim();
    final ep = _episodeLabel(e);
    final who = e.watchedWithUsername;
    final rating = e.rating;
    final tags = <String>[
      ...e.moodTags.take(3),
      if (e.isRewatch) _l('пересмотр', 'rewatch'),
      if (who != null && who.isNotEmpty) _l('с $who', 'with $who'),
    ];

    return _dogEar(
      pw.Container(
        width: _contentW,
        padding: const pw.EdgeInsets.fromLTRB(16, 16, 20, 16),
        decoration: pw.BoxDecoration(
          color: _paper,
          borderRadius: pw.BorderRadius.circular(16),
          border: pw.Border.all(color: _border, width: 0.8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(4, 6, 0, 0),
              child: _polaroidWidget(
                posters: posters,
                url: e.posterUrl,
                title: e.displayTitle,
                color: color,
                width: 88,
                height: 126,
                fonts: fonts,
                tilt: index.isEven ? -0.045 : 0.045,
                tape: color,
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _dayBlock(e, color, fonts),
                      pw.SizedBox(width: 10),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: _pill(mediaTypeLabel(e.mediaType), color, fonts),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(_clip(e.displayTitle, 70), maxLines: 2, style: _t(fonts.display, 12.5, _ink, lh: 1.6)),
                  if (ep != null) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(ep, style: _t(fonts.body, 8, _inkMuted)),
                  ],
                  pw.SizedBox(height: 8),
                  if (rating != null)
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        _hearts(rating, size: 9, gap: 1.6),
                        pw.SizedBox(width: 8),
                        pw.Text('$rating/10', style: _t(fonts.bodyBold, 8.5, _ratingColor(rating))),
                      ],
                    ),
                  if (tags.isNotEmpty) ...[
                    pw.SizedBox(height: 9),
                    pw.Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (var i = 0; i < tags.length; i++)
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2.4),
                            decoration: pw.BoxDecoration(
                              color: _mix(_paper, _wrappedRotation[(i + 2) % _wrappedRotation.length], 0.32),
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Text(_clip(tags[i], 26), style: _t(fonts.body, 7.6, _ink)),
                          ),
                      ],
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    pw.SizedBox(height: 11),
                    pw.Container(
                      padding: const pw.EdgeInsets.only(left: 10),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(left: pw.BorderSide(color: color, width: 2)),
                      ),
                      child: pw.Text(_clip(note, 300), style: _t(fonts.handBold, 15, _ink, lh: 1.5)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      color,
      fold: 18,
    );
  }

  // ---- Back cover / closing -------------------------------------------

  static pw.Page _closingPage({
    required _Fonts fonts,
    required pw.MemoryImage? mascot,
    required bool backCover,
    required String line,
  }) {
    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) =>
            _fullPage((c, s) => backCover ? _paintCover(c, s, 8) : _paintNight(c, s, 21, null)),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            _mascotRing(mascot, 64, _foil),
            pw.SizedBox(height: 30),
            pw.Text(line, textAlign: pw.TextAlign.center, style: _t(fonts.black, 21, _cream)),
            pw.SizedBox(height: 14),
            _ornament(160, _foil),
            pw.SizedBox(height: 14),
            pw.Text(_l('до следующего вечера', 'see you next evening'), style: _t(fonts.handBold, 26, _foil)),
            pw.SizedBox(height: 34),
            pw.Text(_spaced(_brand), style: _t(fonts.bodyBold, 9, _mix(_plum, _cream, 0.55), ls: 3)),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // WRAPPED
  // =====================================================================

  // Ticket geometry, shared by the page background (shadow) and the card.
  static const double _tkL = 34;
  static const double _tkB = 60;
  static const double _tkW = _pageW - 68; // 527.28
  static const double _tkH = _pageH - 128; // 713.89
  static const double _stubH = 78;
  static const double _tkPad = 30;
  static const double _bodyW = _tkW - _tkPad * 2;

  static Future<Uint8List> buildWrapped({
    required WrappedSummary summary,
    required String personName,
  }) async {
    final fonts = await _loadFonts();
    final mascot = await _loadMascot();
    final posterUrls = <String?>[
      ...summary.posterUrls,
      summary.first?.posterUrl,
      summary.last?.posterUrl,
      summary.favoriteReview?.posterUrl,
      for (final r in summary.topReviews) r.posterUrl,
    ];
    final posters = await _fetchPosters(posterUrls);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.body, bold: fonts.bodyBold),
    );

    var toneIndex = 0;
    PdfColor nextTone() => _wrappedRotation[(toneIndex++) % _wrappedRotation.length];

    final chapters = <_Chapter>[];

    chapters.add(_Chapter(
      tone: nextTone(),
      pattern: 0,
      eyebrow: _l('этот период одним взглядом', 'this period, at a glance'),
      stub: summary.periodLabel,
      body: (fg, tone) => _chOverview(summary, fg, tone, fonts),
    ));

    if (summary.posterUrls.isNotEmpty) {
      final n = math.min(9, summary.posterUrls.length);
      chapters.add(_Chapter(
        tone: _mix(_night, _accent, 0.42),
        pattern: 2,
        eyebrow: _l('экраны этого периода', 'the screens of this period'),
        stub: _l('$n афиш на стене', '$n posters on the wall'),
        body: (fg, tone) => _chPosterWall(summary, fg, tone, fonts, posters),
      ));
    }

    if (summary.decades.isNotEmpty || summary.newCount > 0 || summary.rewatchCount > 0) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 1,
        eyebrow: _l('откуда твои истории', 'where your stories came from'),
        stub: _l('впервые и снова', 'new and again'),
        body: (fg, tone) => _chBreakdown(summary, fg, tone, fonts),
      ));
    }

    if (summary.first != null || summary.last != null) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 0,
        eyebrow: _l('первый и последний вечер', 'first & last evening'),
        stub: summary.daysSpan > 0 ? _daysLabel(summary.daysSpan) : summary.periodLabel,
        body: (fg, tone) => _chFirstLast(summary, fg, tone, fonts, posters),
      ));
    }

    if (summary.genreMix.isNotEmpty) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 1,
        eyebrow: _l('жанры этого периода', 'genres of this period'),
        stub: summary.topGenre ?? '',
        body: (fg, tone) => _chGenres(summary, fg, tone, fonts),
      ));
    }

    if (summary.weekdays.any((d) => d.count > 0)) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 2,
        eyebrow: _l('какой день — твой', 'your kind of day'),
        stub: _l('выходные — ${summary.weekendPercent.round()}%', 'weekends — ${summary.weekendPercent.round()}%'),
        body: (fg, tone) => _chRhythm(summary, fg, tone, fonts),
      ));
    }

    if (summary.timeline.length > 1 && summary.timeline.any((b) => b.count > 0)) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 0,
        eyebrow: summary.scope == 'month'
            ? _l('как шёл месяц', 'how the month went')
            : _l('как шёл период', 'how the period went'),
        stub: summary.busiestTimelineLabel ?? '',
        body: (fg, tone) => _chTimeline(summary, fg, tone, fonts),
      ));
    }

    final peak = summary.peakHour;
    chapters.add(_Chapter(
      tone: nextTone(),
      pattern: 1,
      eyebrow: _l('твой типаж периода', 'your archetype this period'),
      stub: peak != null
          ? _l('пик в ${peak.toString().padLeft(2, '0')}:00', 'peak at ${peak.toString().padLeft(2, '0')}:00')
          : '',
      body: (fg, tone) => _chArchetype(summary, fg, tone, fonts),
    ));

    if (summary.topDirectors.isNotEmpty) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 2,
        eyebrow: _l('кого ты смотрел чаще всего', 'the names you kept coming back to'),
        stub: _clip(summary.topDirectors.first.name, 26),
        body: (fg, tone) => _chDirectors(summary, fg, tone, fonts),
      ));
    }

    if (summary.reviewCount > 0) {
      chapters.add(_Chapter(
        tone: nextTone(),
        pattern: 0,
        eyebrow: _l('твои оценки', 'how you rated it'),
        stub: _l('${summary.reviewCount} отзывов', '${summary.reviewCount} reviews'),
        body: (fg, tone) => _chReviews(summary, fg, tone, fonts, posters),
      ));
    }

    // Page numbers count every page: cover = 1, chapters, receipt, closing.
    final hasReceipt = summary.receiptItems.isNotEmpty;
    final total = chapters.length + 2 + (hasReceipt ? 1 : 0);

    doc.addPage(_wrappedCover(summary: summary, personName: personName, fonts: fonts, mascot: mascot, posters: posters));
    for (var i = 0; i < chapters.length; i++) {
      doc.addPage(_ticketPage(chapters[i], i + 2, total, fonts));
    }
    if (hasReceipt) {
      doc.addPage(_wrappedReceiptPage(summary: summary, fonts: fonts, index: chapters.length + 2, total: total));
    }
    doc.addPage(_closingPage(fonts: fonts, mascot: mascot, backCover: false, line: _thanksLine(summary.scope)));

    return doc.save();
  }

  // ---- Cover ----------------------------------------------------------

  static pw.Page _wrappedCover({
    required WrappedSummary summary,
    required String personName,
    required _Fonts fonts,
    required pw.MemoryImage? mascot,
    required Map<String, pw.MemoryImage> posters,
  }) {
    final urls = <String?>[
      for (var i = 0; i < 3; i++) i < summary.posterUrls.length ? summary.posterUrls[i] : null,
    ];
    final tones = [_coral, _mustard, _periwinkle];
    pw.Widget fan(int i, double tilt) => _polaroidWidget(
          posters: posters,
          url: urls[i],
          title: '',
          color: tones[i],
          width: 118,
          height: 168,
          fonts: fonts,
          border: 5,
          tilt: tilt,
          tape: tones[(i + 1) % 3],
        );

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage((c, s) {
          _paintNight(c, s, 5, null);
          c.setStrokeColor(_mix(_night, _foil, 0.28));
          c.setLineWidth(0.9);
          for (var i = 1; i <= 5; i++) {
            c.drawEllipse(s.x / 2, s.y * 0.58, 90.0 + i * 46, 90.0 + i * 46);
            c.strokePath();
          }
        }),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(_spaced(_brand), style: _t(fonts.bodyBold, 11, _foil, ls: 3)),
            pw.SizedBox(height: 44),
            pw.SizedBox(
              width: 440,
              height: 220,
              child: pw.Stack(
                overflow: pw.Overflow.visible,
                children: [
                  pw.Positioned(left: 8, top: 24, child: fan(0, 0.16)),
                  pw.Positioned(left: 306, top: 24, child: fan(2, -0.16)),
                  pw.Positioned(left: 156, top: 0, child: fan(1, 0)),
                ],
              ),
            ),
            pw.SizedBox(height: 46),
            pw.Text('WRAPPED', style: _t(fonts.black, 46, _cream, ls: 4)),
            pw.SizedBox(height: 10),
            pw.Text(summary.periodLabel, style: _t(fonts.handBold, 38, _foil)),
            if (summary.rangeLabel.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(summary.rangeLabel, style: _t(fonts.body, 10, _mix(_night, _cream, 0.6))),
            ],
            pw.SizedBox(height: 26),
            _ornament(190, _foil),
            pw.SizedBox(height: 18),
            if (personName.isNotEmpty) pw.Text(personName, style: _t(fonts.display, 14, _cream)),
            pw.SizedBox(height: 6),
            pw.Text(
              '${_eveningsLabel(summary.totalLogged)}  ·  ${_hoursLabel(summary.totalHours)}',
              style: _t(fonts.body, 10, _mix(_night, _cream, 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Ticket scaffold ------------------------------------------------

  static pw.Page _ticketPage(_Chapter ch, int index, int total, _Fonts fonts) {
    final fg = _onTone(ch.tone);
    final soft = _mix(ch.tone, fg, 0.55);

    final card = pw.SizedBox(
      width: _tkW,
      height: _tkH,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.CustomPaint(painter: (c, s) => _paintTicket(c, s, ch.tone, fg, ch.pattern)),
          ),
          pw.Positioned(
            left: _tkPad,
            right: _tkPad,
            top: 30,
            bottom: _stubH + 18,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  _sparkleWidget(5, soft),
                  pw.SizedBox(width: 7),
                  pw.Text(ch.eyebrow.toUpperCase(), style: _t(fonts.bodyBold, 8.6, soft, ls: 1.8)),
                ]),
                pw.SizedBox(height: 20),
                pw.Expanded(child: ch.body(fg, ch.tone)),
              ],
            ),
          ),
          pw.Positioned(
            left: _tkPad,
            right: _tkPad,
            bottom: 0,
            child: pw.SizedBox(
              height: _stubH,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(index.toString().padLeft(2, '0'), style: _t(fonts.black, 24, fg)),
                  pw.Text(' / ${total.toString().padLeft(2, '0')}', style: _t(fonts.bodyBold, 9, soft)),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Text(_clip(ch.stub, 34), maxLines: 1, style: _t(fonts.handBold, 19, fg)),
                    ),
                  ),
                  _barcode(74, 24, soft, 40 + index),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage(
          (c, s) => _paintNight(c, s, 100 + index, [_tkL, _tkB, _tkW, _tkH]),
        ),
      ),
      build: (context) => pw.Stack(
        children: [
          pw.Positioned(left: _tkL, bottom: _tkB, child: card),
          pw.Positioned(
            left: _tkL + 4,
            top: 26,
            child: pw.Text('$_brand · wrapped', style: _t(fonts.bodyBold, 8, _mix(_night, _cream, 0.55), ls: 1.4)),
          ),
          pw.Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: pw.Center(child: _progressDots(index - 1, total)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _progressDots(int active, int total) => pw.CustomPaint(
        size: PdfPoint(total * 12.0, 8),
        painter: (c, s) {
          for (var i = 0; i < total; i++) {
            final on = i == active;
            _fillCircle(c, on ? _foil : _mix(_night, _cream, 0.28), i * 12.0 + 4, 4, on ? 3.4 : 2);
          }
        },
      );

  /// Ticket shape: rounded card, two punched notches on the perforation
  /// line above the stub, a dashed tear line, and a corner pattern
  /// clipped to the card so it can bleed off the edge.
  static void _paintTicket(PdfGraphics c, PdfPoint s, PdfColor tone, PdfColor fg, int pattern) {
    final w = s.x;
    final h = s.y;
    c.setFillColor(tone);
    _rr(c, 0, 0, w, h, 26);
    c.fillPath();

    final tint = _mix(tone, fg, 0.09);
    c.saveContext();
    _rr(c, 0, 0, w, h, 26);
    c.clipPath();
    if (pattern == 0) {
      c.setStrokeColor(tint);
      c.setLineWidth(1.2);
      for (var i = 1; i <= 7; i++) {
        c.drawEllipse(w * 0.98, h * 0.99, i * 38.0, i * 38.0);
        c.strokePath();
      }
    } else if (pattern == 1) {
      _fillCircle(c, tint, w * 0.92, h * 0.93, 120);
      _fillCircle(c, _mix(tone, fg, 0.06), w * 0.05, h * 0.3, 70);
    } else {
      c.setStrokeColor(tint);
      c.setLineWidth(1.2);
      for (var i = -12; i < 22; i++) {
        c.moveTo(i * 30.0, h);
        c.lineTo(i * 30.0 + 260, h - 260);
        c.strokePath();
      }
    }
    c.restoreContext();

    // The tear line and the notches.
    c.setStrokeColor(_mix(tone, fg, 0.42));
    c.setLineWidth(1.1);
    c.setLineDashPattern([5, 4]);
    c.moveTo(22, _stubH);
    c.lineTo(w - 22, _stubH);
    c.strokePath();
    c.setLineDashPattern();
    _fillCircle(c, _night, 0, _stubH, 12);
    _fillCircle(c, _night, w, _stubH, 12);
  }

  // ---- Chapters -------------------------------------------------------

  static pw.Widget _statTile(String value, String label, PdfColor fg, PdfColor tone, _Fonts fonts) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(12, 13, 12, 11),
          decoration: pw.BoxDecoration(
            color: _mix(tone, fg, 0.14),
            borderRadius: pw.BorderRadius.circular(14),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _fit(pw.Text(value, style: _t(fonts.black, 15, fg))),
              pw.SizedBox(height: 5),
              pw.Text(label, style: _t(fonts.body, 8, _mix(tone, fg, 0.8))),
            ],
          ),
        ),
      );

  static pw.Widget _bar(double width, double height, double fraction, PdfColor track, PdfColor fill) =>
      pw.Container(
        width: width,
        height: height,
        decoration: pw.BoxDecoration(color: track, borderRadius: pw.BorderRadius.circular(height / 2)),
        child: pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: math.max(height, width * fraction.clamp(0.0, 1.0).toDouble()),
            height: height,
            decoration: pw.BoxDecoration(color: fill, borderRadius: pw.BorderRadius.circular(height / 2)),
          ),
        ),
      );

  static pw.Widget _chOverview(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        _fit(pw.Text('${s.totalLogged}', style: _t(fonts.black, 132, fg))),
        pw.SizedBox(height: 4),
        pw.Text(
          _l(_pluralRu(s.totalLogged, 'вечер записан', 'вечера записано', 'вечеров записано'),
              s.totalLogged == 1 ? 'evening logged' : 'evenings logged'),
          style: _t(fonts.display, 15, fg),
        ),
        pw.SizedBox(height: 28),
        _dashedRule(_bodyW, _mix(tone, fg, 0.4)),
        pw.SizedBox(height: 28),
        pw.Row(children: [
          _statTile(_hoursLabel(s.totalHours), _l('у экрана', 'behind the screen'), fg, tone, fonts),
          pw.SizedBox(width: 8),
          _statTile(_daysLabel(s.daysSpan), _l('от первого до последнего', 'first to last'), fg, tone, fonts),
          if (s.longestStreakDays > 0) ...[
            pw.SizedBox(width: 8),
            _statTile(_daysLabel(s.longestStreakDays), _l('лучший стрик', 'longest streak'), fg, tone, fonts),
          ],
        ]),
        pw.SizedBox(height: 22),
        pw.Text(
          _l('${s.totalLogged} записей — и каждая про тебя.',
              '${s.totalLogged} entries — and every one of them is about you.'),
          style: _t(fonts.handBold, 22, fg),
        ),
      ],
    );
  }

  static pw.Widget _chPosterWall(
      WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    final urls = s.posterUrls.take(9).toList();
    pw.Widget col(int c, double topPad) {
      final idx = [for (var i = c; i < urls.length; i += 3) i];
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: topPad),
        child: pw.Column(
          children: [
            for (final i in idx)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: _polaroidWidget(
                  posters: posters,
                  url: urls[i],
                  title: '',
                  color: _wrappedRotation[i % _wrappedRotation.length],
                  width: 106,
                  height: 138,
                  fonts: fonts,
                  border: 4,
                  tilt: i.isEven ? 0.035 : -0.035,
                  tape: _wrappedRotation[(i + 1) % _wrappedRotation.length],
                ),
              ),
          ],
        ),
      );
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        col(0, 4),
        pw.SizedBox(width: 14),
        col(1, 30),
        pw.SizedBox(width: 14),
        col(2, 4),
      ],
    );
  }

  static pw.Widget _chBreakdown(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final decades = s.decades.where((d) => d.count > 0).take(6).toList();
    final track = _mix(tone, fg, 0.16);
    final totalSplit = s.newCount + s.rewatchCount;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (decades.isNotEmpty) ...[
          pw.Text(_l('по десятилетиям', 'by decade'), style: _t(fonts.handBold, 24, fg)),
          pw.SizedBox(height: 14),
          for (final d in decades)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 15),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(d.label, style: _t(fonts.display, 12, fg)),
                      pw.Text('${d.count}', style: _t(fonts.black, 12, fg)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  _bar(_bodyW, 12, d.percent / 100, track, fg),
                ],
              ),
            ),
        ],
        if (totalSplit > 0) ...[
          pw.SizedBox(height: 10),
          _dashedRule(_bodyW, _mix(tone, fg, 0.4)),
          pw.SizedBox(height: 22),
          pw.Text(_l('впервые или снова', 'new or again'), style: _t(fonts.handBold, 24, fg)),
          pw.SizedBox(height: 14),
          pw.CustomPaint(
            size: const PdfPoint(_bodyW, 22),
            painter: (c, sz) {
              final wNew = sz.x * s.newCount / totalSplit;
              c.setFillColor(track);
              _rr(c, 0, 0, sz.x, sz.y, 11);
              c.fillPath();
              if (s.newCount > 0) {
                c.setFillColor(fg);
                _rr(c, 0, 0, math.max(22.0, wNew), sz.y, 11);
                c.fillPath();
              }
            },
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${s.newCount} ${_l('впервые', 'first watches')}', style: _t(fonts.bodyBold, 10, fg)),
              pw.Text('${s.rewatchCount} ${_l('пересмотров', 'rewatches')}', style: _t(fonts.bodyBold, 10, fg)),
            ],
          ),
        ],
      ],
    );
  }

  static pw.Widget _chFirstLast(
      WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    pw.Widget moment(WrappedTitleMoment m, String tag, double tilt, PdfColor tape) => pw.Column(
          children: [
            _polaroidWidget(
              posters: posters,
              url: m.posterUrl,
              title: m.title,
              color: _mix(tone, fg, 0.25),
              width: 150,
              height: 214,
              fonts: fonts,
              border: 6,
              tilt: tilt,
              tape: tape,
              caption: tag,
            ),
            pw.SizedBox(height: 16),
            pw.SizedBox(
              width: 170,
              child: pw.Text(_clip(m.title, 40),
                  textAlign: pw.TextAlign.center, maxLines: 2, style: _t(fonts.display, 11, fg, lh: 1.5)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(m.dateLabel, style: _t(fonts.body, 9, _mix(tone, fg, 0.75))),
          ],
        );

    final first = s.first;
    final last = s.last;
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (first != null) moment(first, _l('первый', 'first'), -0.05, _mustard),
            if (first != null && last != null) pw.SizedBox(width: 34),
            if (last != null) moment(last, _l('последний', 'latest'), 0.05, _periwinkle),
          ],
        ),
        if (s.daysSpan > 0) ...[
          pw.SizedBox(height: 26),
          pw.Text(_l('между ними — ${_daysLabel(s.daysSpan)}', 'between them — ${_daysLabel(s.daysSpan)}'),
              style: _t(fonts.handBold, 24, fg)),
        ],
      ],
    );
  }

  static pw.Widget _chGenres(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final genres = s.genreMix.take(6).toList();
    final top = genres.first;
    final track = _mix(tone, fg, 0.16);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_l('больше всего —', 'mostly —'), style: _t(fonts.handBold, 26, fg)),
        pw.SizedBox(height: 4),
        _fit(pw.Text(top.genre, style: _t(fonts.black, 46, fg))),
        pw.SizedBox(height: 2),
        pw.Text('${top.percent.round()}%  ·  ${_eveningsLabel(top.count)}', style: _t(fonts.bodyBold, 12, fg)),
        pw.SizedBox(height: 26),
        for (var i = 1; i < genres.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(genres[i].genre, style: _t(fonts.display, 12, fg)),
                    pw.Text('${genres[i].percent.round()}%', style: _t(fonts.black, 12, fg)),
                  ],
                ),
                pw.SizedBox(height: 6),
                _bar(_bodyW, 10, genres[i].percent / 100, track, fg),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _chRhythm(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final counts = List<int>.filled(7, 0);
    for (final d in s.weekdays) {
      if (d.weekday >= 0 && d.weekday < 7) counts[d.weekday] = d.count;
    }
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    final maxCount = counts[best];
    final labels = LocaleService.appIsRussian ? _weekdayShortRu : _weekdayShortEn;
    final names = LocaleService.appIsRussian ? _weekdayFullRu : _weekdayFullEn;
    final track = _mix(tone, fg, 0.3);
    const chartH = 210.0;
    final busiest = s.busiestTimelineLabel;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_l('твой день —', 'your day is'), style: _t(fonts.handBold, 26, fg)),
        pw.SizedBox(height: 2),
        _fit(pw.Text(names[best], style: _t(fonts.black, 42, fg))),
        pw.SizedBox(height: 26),
        pw.SizedBox(
          height: chartH + 30,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text('${counts[i]}', style: _t(fonts.bodyBold, 9, fg)),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        width: 34,
                        height: maxCount == 0 ? 6 : 8 + (counts[i] / maxCount) * (chartH - 20),
                        decoration: pw.BoxDecoration(
                          color: i == best ? fg : track,
                          borderRadius: pw.BorderRadius.circular(9),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(labels[i].toUpperCase(),
                          style: _t(i == best || i >= 5 ? fonts.bodyBold : fonts.body, 8.5, fg, ls: 1)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 22),
        if (busiest != null)
          pw.Text(
            _l('самый насыщенный день — $busiest', 'busiest day — $busiest'),
            style: _t(fonts.handBold, 22, fg),
          ),
      ],
    );
  }

  static pw.Widget _chTimeline(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final buckets = s.timeline.take(31).toList();
    final maxCount = buckets.map((b) => b.count).reduce(math.max);
    final step = buckets.length > 16 ? (buckets.length > 24 ? 4 : 2) : 1;
    final track = _mix(tone, fg, 0.3);
    const chartH = 250.0;
    final busiest = s.busiestTimelineLabel;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          busiest != null ? _l('пик — $busiest', 'peak — $busiest') : _l('вечер за вечером', 'evening by evening'),
          style: _t(fonts.handBold, 28, fg),
        ),
        pw.SizedBox(height: 28),
        pw.SizedBox(
          height: chartH + 24,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: math.max(3.0, math.min(22.0, _bodyW / buckets.length - 4)),
                        height: buckets[i].count == 0 ? 3 : 8 + (buckets[i].count / maxCount) * (chartH - 12),
                        decoration: pw.BoxDecoration(
                          color: buckets[i].count == maxCount ? fg : track,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.SizedBox(
                        height: 10,
                        child: i % step == 0
                            ? pw.Text(buckets[i].label, style: _t(fonts.body, 7, fg))
                            : pw.SizedBox(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _chArchetype(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final peak = s.peakHour;
    final genre = s.topGenre;
    final chips = <String>[
      if (peak != null)
        _l('пик в ${peak.toString().padLeft(2, '0')}:00', 'peak at ${peak.toString().padLeft(2, '0')}:00'),
      _l(s.soloPercent >= 50 ? 'чаще всего одна' : 'чаще всего с кем-то',
          s.soloPercent >= 50 ? 'mostly solo' : 'mostly with someone'),
      if (genre != null) '${_l('жанр', 'top genre')} — $genre',
      if (s.longestStreakDays > 0) '${_l('стрик', 'streak')} — ${_daysLabel(s.longestStreakDays)}',
      if (s.topDirectors.isNotEmpty) '${_l('режиссёр', 'top director')} — ${_clip(s.topDirectors.first.name, 22)}',
    ];
    final track = _mix(tone, fg, 0.16);
    final solo = s.soloPercent.clamp(0.0, 100.0).toDouble();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.CustomPaint(
          size: const PdfPoint(96, 96),
          painter: (c, sz) {
            _sparkle(c, _mix(tone, fg, 0.22), 48, 48, 48);
            _sparkle(c, fg, 48, 48, 26);
          },
        ),
        pw.SizedBox(height: 22),
        pw.SizedBox(
          width: _bodyW,
          child: _fit(
            pw.Text(s.archetypeLabel.isNotEmpty ? s.archetypeLabel : '—', style: _t(fonts.black, 34, fg)),
            alignment: pw.Alignment.center,
          ),
        ),
        pw.SizedBox(height: 26),
        pw.Wrap(
          spacing: 9,
          runSpacing: 10,
          alignment: pw.WrapAlignment.center,
          children: [
            for (var i = 0; i < chips.length; i++)
              pw.Transform.rotate(
                angle: i.isEven ? -0.03 : 0.03,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: i.isEven ? fg : track,
                    borderRadius: pw.BorderRadius.circular(16),
                  ),
                  child: pw.Text(chips[i], style: _t(fonts.bodyBold, 10, i.isEven ? tone : fg)),
                ),
              ),
          ],
        ),
        if (s.soloCount + s.companyCount > 0) ...[
          pw.SizedBox(height: 34),
          pw.CustomPaint(
            size: PdfPoint(_bodyW * 0.8, 16),
            painter: (c, sz) {
              c.setFillColor(track);
              _rr(c, 0, 0, sz.x, sz.y, 8);
              c.fillPath();
              c.setFillColor(fg);
              _rr(c, 0, 0, math.max(16.0, sz.x * solo / 100), sz.y, 8);
              c.fillPath();
            },
          ),
          pw.SizedBox(height: 8),
          pw.SizedBox(
            width: _bodyW * 0.8,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${_l('одна', 'solo')} ${solo.round()}%', style: _t(fonts.bodyBold, 9.5, fg)),
                pw.Text('${_l('с кем-то', 'with someone')} ${(100 - solo).round()}%',
                    style: _t(fonts.bodyBold, 9.5, fg)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _chDirectors(WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts) {
    final list = s.topDirectors.take(5).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        for (var i = 0; i < list.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 22),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 74,
                  child: pw.Text('${i + 1}',
                      style: _t(fonts.black, i == 0 ? 60 : 40, i == 0 ? fg : _mix(tone, fg, 0.5))),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(_clip(list[i].name, 32),
                          maxLines: 2, style: _t(fonts.display, i == 0 ? 17 : 13, fg, lh: 1.4)),
                      pw.SizedBox(height: 4),
                      pw.Text(_eveningsLabel(list[i].count), style: _t(fonts.body, 9.5, _mix(tone, fg, 0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _chReviews(
      WrappedSummary s, PdfColor fg, PdfColor tone, _Fonts fonts, Map<String, pw.MemoryImage> posters) {
    final fav = s.favoriteReview;
    final counts = List<int>.filled(10, 0);
    for (final b in s.ratingHistogram) {
      if (b.rating >= 1 && b.rating <= 10) counts[b.rating - 1] = b.count;
    }
    final maxHist = counts.reduce(math.max);
    final track = _mix(tone, fg, 0.3);
    final favNote = (fav?.note ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          _statTile('${s.reviewCount}', _l('отзывов', 'reviews'), fg, tone, fonts),
          pw.SizedBox(width: 8),
          _statTile(s.averageRating.toStringAsFixed(1), _l('средняя оценка', 'average rating'), fg, tone, fonts),
          if (s.fullMarksCount > 0) ...[
            pw.SizedBox(width: 8),
            _statTile('${s.fullMarksCount}', _l('десяток', 'perfect 10s'), fg, tone, fonts),
          ],
        ]),
        if (maxHist > 0) ...[
          pw.SizedBox(height: 22),
          pw.SizedBox(
            height: 74,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 10; i++)
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Container(
                          width: 20,
                          height: counts[i] == 0 ? 3 : 6 + (counts[i] / maxHist) * 44,
                          decoration: pw.BoxDecoration(
                            color: counts[i] == maxHist ? fg : track,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('${i + 1}', style: _t(fonts.body, 7.5, fg)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (fav != null) ...[
          pw.SizedBox(height: 26),
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: _mix(tone, fg, 0.12),
              borderRadius: pw.BorderRadius.circular(18),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: _polaroidWidget(
                    posters: posters,
                    url: fav.posterUrl,
                    title: fav.title,
                    color: _mix(tone, fg, 0.3),
                    width: 78,
                    height: 112,
                    fonts: fonts,
                    border: 4,
                    tilt: -0.05,
                    tape: _mustard,
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(_l('любимый отзыв', 'favorite review').toUpperCase(),
                          style: _t(fonts.bodyBold, 7.6, _mix(tone, fg, 0.8), ls: 1.4)),
                      pw.SizedBox(height: 5),
                      pw.Text(_clip(fav.title, 44), maxLines: 2, style: _t(fonts.display, 12, fg, lh: 1.5)),
                      if (fav.rating != null) ...[
                        pw.SizedBox(height: 7),
                        _hearts(fav.rating, size: 8.5, gap: 1.4, fill: fg, empty: _mix(tone, fg, 0.4)),
                      ],
                      if (favNote.isNotEmpty) ...[
                        pw.SizedBox(height: 9),
                        pw.Text('“${_clip(favNote, 190)}”', style: _t(fonts.handBold, 15.5, fg, lh: 1.4)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---- Receipt --------------------------------------------------------

  static pw.Page _wrappedReceiptPage({
    required WrappedSummary summary,
    required _Fonts fonts,
    required int index,
    required int total,
  }) {
    final items = summary.receiptItems.take(9).toList();
    final rest = summary.receiptItems.length - items.length;
    const paperW = 320.0;
    final topGenre = summary.topGenre;

    pw.Widget leader(String label, String value, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 190),
                child: pw.Text(_clip(label, 30), maxLines: 1, style: _t(bold ? fonts.bodyBold : fonts.body, 10, _ink)),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: pw.CustomPaint(
                    size: const PdfPoint(10, 2),
                    painter: (c, s) {
                      c.setStrokeColor(_inkFaint);
                      c.setLineWidth(1);
                      c.setLineCap(PdfLineCap.round);
                      c.setLineDashPattern([0.01, 3.2]);
                      c.moveTo(0, 1);
                      c.lineTo(s.x, 1);
                      c.strokePath();
                    },
                  ),
                ),
              ),
              pw.Text(value, style: _t(fonts.bodyBold, 10, _ink)),
            ],
          ),
        );

    pw.Widget rule() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          child: _dashedRule(paperW - 56, _inkFaint, dash: 3, gap: 3),
        );

    final paper = pw.CustomPaint(
      painter: (c, s) {
        const tooth = 7.0;
        void zigzag(double dx, double dy, PdfColor col) {
          c.setFillColor(col);
          final n = (s.x / (tooth * 2)).floor();
          final tw = s.x / n;
          c.moveTo(dx, s.y - tooth + dy);
          for (var i = 0; i < n; i++) {
            c.lineTo(dx + i * tw + tw / 2, s.y + dy);
            c.lineTo(dx + (i + 1) * tw, s.y - tooth + dy);
          }
          c.lineTo(dx + s.x, tooth + dy);
          for (var i = n; i > 0; i--) {
            c.lineTo(dx + i * tw - tw / 2, dy);
            c.lineTo(dx + (i - 1) * tw, tooth + dy);
          }
          c.lineTo(dx, s.y - tooth + dy);
          c.fillPath();
        }

        zigzag(5, -6, _mix(_night, PdfColors.black, 0.45));
        zigzag(0, 0, _paper);
      },
      child: pw.Container(
        width: paperW,
        padding: const pw.EdgeInsets.fromLTRB(28, 34, 28, 34),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text(_brand.toUpperCase(), style: _t(fonts.black, 20, _ink, ls: 3))),
            pw.SizedBox(height: 5),
            pw.Center(
              child: pw.Text('${_l('чек', 'receipt')} · ${summary.rangeLabel}', style: _t(fonts.body, 9, _inkMuted)),
            ),
            rule(),
            pw.Center(
              child: pw.Text(
                _l('${summary.receiptItems.length} ${_pluralRu(summary.receiptItems.length, 'позиция', 'позиции', 'позиций')}',
                        '${summary.receiptItems.length} ${summary.receiptItems.length == 1 ? 'item' : 'items'}')
                    .toUpperCase(),
                style: _t(fonts.bodyBold, 8, _inkFaint, ls: 1.4),
              ),
            ),
            rule(),
            for (final it in items) leader(it.title, '×${it.count}'),
            if (rest > 0) pw.Text(_l('+ $rest ещё', '+ $rest more items'), style: _t(fonts.hand, 14, _inkFaint)),
            rule(),
            if (summary.longestStreakDays > 0)
              leader(
                _l('стрик ${_daysLabel(summary.longestStreakDays)}', 'streak ${_daysLabel(summary.longestStreakDays)}'),
                _l('+1 значок', '+1 badge'),
              ),
            if (summary.rewatchCount > 0) leader(_l('пересмотры', 'rewatches'), '×${summary.rewatchCount}'),
            rule(),
            leader(_l('итого времени', 'total time'), _hoursLabel(summary.totalHours), bold: true),
            if (topGenre != null) leader(_l('топ жанр', 'top genre'), topGenre, bold: true),
            rule(),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(_thanksLine(summary.scope), style: _t(fonts.handBold, 20, _accent)),
                  pw.SizedBox(width: 6),
                  _singleHeart(11, _pink),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Center(child: _barcode(170, 34, _ink, 7)),
          ],
        ),
      ),
    );

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage((c, s) => _paintNight(c, s, 100 + index, null)),
      ),
      build: (context) => pw.Stack(
        children: [
          pw.Positioned.fill(child: pw.Center(child: paper)),
          pw.Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: pw.Center(child: _progressDots(index - 1, total)),
          ),
        ],
      ),
    );
  }
}

class _Fonts {
  final pw.Font display; // Unbounded Bold — headings
  final pw.Font black; // Unbounded Black — big numerals
  final pw.Font body; // Comfortaa Regular
  final pw.Font bodyBold; // Comfortaa Bold
  final pw.Font hand; // Caveat
  final pw.Font handBold; // Caveat Bold
  const _Fonts({
    required this.display,
    required this.black,
    required this.body,
    required this.bodyBold,
    required this.hand,
    required this.handBold,
  });
}

class _Chapter {
  final PdfColor tone;
  final int pattern; // 0 rings, 1 soft circles, 2 diagonal lines
  final String eyebrow;
  final String stub;
  final pw.Widget Function(PdfColor fg, PdfColor tone) body;
  const _Chapter({
    required this.tone,
    required this.pattern,
    required this.eyebrow,
    required this.stub,
    required this.body,
  });
}
