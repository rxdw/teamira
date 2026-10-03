import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/circle_review.dart';
import '../models/evenings_book.dart';
import '../screens/partner/room/room_strings.dart' show clockLabel, emotionLabel, verdictLine;
import '../utils/book_text.dart';
import 'locale_service.dart';

/// Builds the premium "book of your evenings" — the circle's joint reviews
/// and the moments of its room evenings as a keepsake PDF.
///
/// It is the sibling of [KeepsakePdfService] (the personal diary book) and
/// deliberately speaks the same language: the plum, foil-stamped cover, warm
/// dot-grid paper, polaroids held by washi tape, painted hearts and
/// handwriting. What is different is the content — every evening is a *card
/// of several voices*: the shared score and the verdict first, then what each
/// person gave, wrote and tagged, and for room evenings the timeline of the
/// moments the circle felt together.
///
/// What goes in is decided by the server (see `GET /partner/reviews/book`):
/// only opened reviews, only ones somebody actually wrote in. This class
/// decides how it looks and what survives the fonts:
///  - The bundled PDF fonts (assets/pdf_fonts) are Latin + Cyrillic subsets
///    with no emoji, so everything a person typed goes through [pdfSafe]
///    and moments are printed as words, never as the app's emoji.
///  - Hearts are painted (the fonts have no heart glyph), one per rating
///    point on the app's real 1–10 scale.
///  - No color alpha anywhere: the `pdf` package ignores it on fills, so
///    every soft tone is pre-blended with [_mix].
///
/// Kept self-contained on purpose: [KeepsakePdfService] is a working premium
/// export and is not touched here. The painting primitives below are the same
/// ones, checked against the `pdf` 3.13 sources, and can be folded into one
/// shared kit later.
class EveningsBookPdfService {
  const EveningsBookPdfService._();

  static const _brand = 'tanè';

  // ---------------------------------------------------------------------
  // Palette — the same tokens as the diary keepsake (themselves mirroring
  // SeenlyPalette), so the two books sit on one shelf.
  // ---------------------------------------------------------------------
  static const _background = PdfColor.fromInt(0xFFF5EFE4);
  static const _paper = PdfColor.fromInt(0xFFFFFDF8);
  static const _polaroid = PdfColor.fromInt(0xFFFFFDF7);
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
  static const _plum = PdfColor.fromInt(0xFF3B2733);
  static const _foil = PdfColor.fromInt(0xFFDDB877);

  /// One tone per person of the circle, in the circle's order, so somebody
  /// keeps their color from the first page to the last.
  static const _personTones = [_accent, _sage, _mustard, _periwinkle, _clay, _coral];

  static const double _pageW = 595.28;
  static const double _pageH = 841.89;
  static const double _contentW = _pageW - 68;

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

  static PdfColor _verdictColor(String verdict) => switch (verdict) {
        'unison' => _sage,
        'close' => _mustard,
        'split' => _coral,
        _ => _inkFaint,
      };

  static PdfColor _mix(PdfColor a, PdfColor b, double t) => PdfColor(
        a.red + (b.red - a.red) * t,
        a.green + (b.green - a.green) * t,
        a.blue + (b.blue - a.blue) * t,
      );

  static bool _isLight(PdfColor c) => (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) > 0.58;

  static PdfColor _onTone(PdfColor bg) => _isLight(bg) ? _ink : _cream;

  /// Warmer with a higher score, same idea as SeenlyPalette.ratingColor.
  static PdfColor _ratingColor(int r) => _mix(_accent, _pink, ((r - 1) / 9).clamp(0.0, 1.0).toDouble());

  // ---------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------

  static bool get _ru => LocaleService.appIsRussian;

  static String _l(String ru, String en) => _ru ? ru : en;

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

  static String _monthName(int m) => (_ru ? _monthNamesRu : _monthNamesEn)[m];
  static String _monthShort(int m) => (_ru ? _monthShortRu : _monthShortEn)[m];
  static String _monthYear(DateTime d) => '${_monthName(d.month)} ${d.year}';

  /// "сб · 14 мар 2026"
  static String _dayLabel(DateTime d) =>
      '${(_ru ? _weekdayShortRu : _weekdayShortEn)[d.weekday - 1]} · ${d.day} ${_monthShort(d.month)} ${d.year}';

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

  static String _eveningsLabel(int n) =>
      _ru ? '$n ${_pluralRu(n, 'вечер', 'вечера', 'вечеров')}' : '$n ${n == 1 ? 'evening' : 'evenings'}';

  /// 8 -> "8", 8.25 -> "8,3" (ru) / "8.3" (en).
  static String _num(double v) {
    final r = (v * 10).round() / 10;
    final s = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return _ru ? s.replaceAll('.', ',') : s;
  }

  static String _typeLabel(String mediaType) => switch (mediaType) {
        'movie' => _l('фильм', 'film'),
        'series' => _l('сериал', 'series'),
        'game' => _l('игра', 'game'),
        'anime' => _l('аниме', 'anime'),
        'book' => _l('книга', 'book'),
        'manga' => _l('манга', 'manga'),
        'video' => _l('видео', 'video'),
        _ => pdfSafe(mediaType),
      };

  static String _spaced(String s) => s.toUpperCase().split('').join(' ');

  // ---------------------------------------------------------------------
  // Fonts and images
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

  /// Most posters one book will fetch; a poster that fails (or is past the
  /// cap) is replaced by a colored initial and never fails the export.
  static const _maxPosters = 200;

  static Future<Map<String, pw.MemoryImage>> _fetchPosters(Iterable<String?> urls, {int batchSize = 8}) async {
    final unique = <String>{
      for (final u in urls)
        if (u != null && u.trim().isNotEmpty) u,
    }.take(_maxPosters).toList();

    final out = <String, pw.MemoryImage>{};
    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.sublist(i, math.min(i + batchSize, unique.length));
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
      // The constructor decodes the bytes, so an undecodable image throws
      // here, inside the try, and not later while the document is saved.
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
  // Low-level painting (same primitives as the diary keepsake)
  // =====================================================================

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
  /// [tint] on a flat [bg].
  static void _glow(PdfGraphics c, double cx, double cy, double r, PdfColor tint, PdfColor bg,
      {double strength = 0.035}) {
    const steps = 8;
    for (var i = 0; i < steps; i++) {
      _fillCircle(c, _mix(bg, tint, strength * (i + 1)), cx, cy, r * (1 - i / steps));
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

  /// Heart (Material "favorite") with its bottom-left at (x, y), [size] wide.
  /// Drawn by hand because the PDF fonts have no heart codepoints.
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
  static pw.Widget _hearts(int? rating, {double size = 7.5, double gap = 1.5, PdfColor? fill}) {
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
            c.setStrokeColor(_dot);
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

  // ---------------------------------------------------------------------
  // Backgrounds — real edge-to-edge fills through PageTheme.buildBackground
  // ---------------------------------------------------------------------

  static pw.Widget _fullPage(void Function(PdfGraphics c, PdfPoint s) painter) => pw.FullPage(
        ignoreMargins: true,
        child: pw.CustomPaint(size: const PdfPoint(_pageW, _pageH), painter: painter),
      );

  /// Warm paper with a bullet-journal dot grid (zero-length round-capped
  /// dashes: ~45 strokes a page instead of ~1,500 circles).
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
        title.isNotEmpty ? title[0].toUpperCase() : '•',
        style: _t(fonts.black, height * 0.34, _mix(color, _cream, 0.8)),
      ),
    );
  }

  /// A photo-print polaroid held by a strip of washi tape, tilted by [tilt]
  /// radians. `Transform.rotate` doesn't change layout size, so callers leave
  /// a few points of slack around it.
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

  // =====================================================================
  // THE BOOK
  // =====================================================================

  /// Assembles the whole document: cover, "at a glance", the evenings month
  /// by month, and a back cover. An empty [book] still yields a valid
  /// two-page document (callers normally don't ask for one).
  static Future<Uint8List> build(EveningsBook book) async {
    final fonts = await _loadFonts();
    final mascot = await _loadMascot();
    final stats = EveningsBookStats.of(book);

    // An evening whose words were all emoji has nothing left to print.
    final printable = [
      for (final r in book.reviews)
        if (r.people.any(_hasSomethingToShow)) r,
    ];
    final posters = await _fetchPosters(printable.map((r) => r.posterUrl));

    final tones = <String, PdfColor>{
      for (var i = 0; i < book.people.length; i++)
        book.people[i].userId: _personTones[i % _personTones.length],
    };

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.body, bold: fonts.bodyBold),
      title: _l('книга ваших вечеров', 'the book of your evenings'),
      author: _brand,
    );

    doc.addPage(_coverPage(
      names: joinNames(book.names, ru: _ru),
      stats: stats,
      fonts: fonts,
      mascot: mascot,
    ));

    if (printable.isNotEmpty) {
      doc.addPage(_glancePage(
        book: book,
        stats: stats,
        fonts: fonts,
        posters: posters,
        tones: tones,
      ));
      doc.addPage(_eveningsMultiPage(
        reviews: printable,
        fonts: fonts,
        posters: posters,
        tones: tones,
      ));
    }

    doc.addPage(_closingPage(fonts: fonts, mascot: mascot));
    return doc.save();
  }

  // ---- Cover -----------------------------------------------------------

  static pw.Page _coverPage({
    required String names,
    required EveningsBookStats stats,
    required _Fonts fonts,
    required pw.MemoryImage? mascot,
  }) {
    final first = stats.first;
    final last = stats.last;
    final rangeLabel =
        (first != null && last != null) ? '${_monthYear(first)}  —  ${_monthYear(last)}' : null;
    final count = stats.evenings;

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage((c, s) => _paintCover(c, s, 7)),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(_spaced(_brand), style: _t(fonts.bodyBold, 11, _foil, ls: 3)),
            pw.SizedBox(height: 26),
            _mascotRing(mascot, 96, _foil),
            pw.SizedBox(height: 34),
            pw.Text(
              _l('книга ваших\nвечеров', 'the book of\nyour evenings'),
              textAlign: pw.TextAlign.center,
              style: _t(fonts.black, 34, _cream, lh: 6),
            ),
            pw.SizedBox(height: 16),
            _ornament(210, _foil),
            pw.SizedBox(height: 30),
            if (names.isNotEmpty)
              pw.Container(
                width: 300,
                padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: pw.BoxDecoration(
                  color: _cream,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _foil, width: 1.6),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(_l('эту книгу написали', 'written by').toUpperCase(),
                        style: _t(fonts.bodyBold, 6.6, _inkMuted, ls: 1.4)),
                    pw.SizedBox(height: 5),
                    _fit(pw.Text(names, style: _t(fonts.handBold, 28, _accent)),
                        alignment: pw.Alignment.center),
                  ],
                ),
              ),
            pw.SizedBox(height: 46),
            pw.Text('$count', style: _t(fonts.black, 54, _foil)),
            pw.SizedBox(height: 4),
            pw.Text(
              count == 0
                  ? _l('пока пусто — но это только начало', 'empty for now — just the beginning')
                  : _l('${_pluralRu(count, 'вечер', 'вечера', 'вечеров')} вместе',
                      count == 1 ? 'evening together' : 'evenings together'),
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

  // ---- At a glance ----------------------------------------------------

  static pw.Page _glancePage({
    required EveningsBook book,
    required EveningsBookStats stats,
    required _Fonts fonts,
    required Map<String, pw.MemoryImage> posters,
    required Map<String, PdfColor> tones,
  }) {
    final names = joinNames(book.names, ru: _ru);
    final first = stats.first;
    final last = stats.last;
    final avg = stats.average;
    final verdictTotal = stats.unison + stats.close + stats.split;

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
                pw.Text(label, style: _t(fonts.body, 8, _inkMuted)),
              ],
            ),
          ),
        );

    pw.Widget sectionLabel(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(text, style: _t(fonts.handBold, 17, _accent)),
        );

    pw.Widget verdictLegend(String label, int n, PdfColor color) => pw.Row(children: [
          pw.Container(
            width: 7,
            height: 7,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 5),
          pw.Text('$label · $n', style: _t(fonts.body, 8, _inkMuted)),
        ]);

    // "3 вечера с шкалой моментов — …": how many room evenings have a
    // timeline, and whether the circle ever felt the same thing at once.
    final timelines = _l(
      '${stats.momentEvenings} ${_pluralRu(stats.momentEvenings, 'вечер', 'вечера', 'вечеров')} с шкалой моментов',
      '${stats.momentEvenings} ${stats.momentEvenings == 1 ? 'evening' : 'evenings'} with a moments timeline',
    );
    final togetherness = stats.sharedMoments == 0
        ? _l('каждый реагировал в своих местах', 'each of you reacted in your own places')
        : _l('общих моментов: ${stats.sharedMoments}', 'shared moments: ${stats.sharedMoments}');
    final momentsSentence = '$timelines — $togetherness';

    final picks = <pw.Widget>[];
    final best = stats.best;
    final disputed = stats.mostDisputed;
    if (best != null) {
      picks.add(_pickCard(
        label: _l('лучший вечер', 'best evening'),
        review: best,
        posters: posters,
        fonts: fonts,
        tilt: -0.03,
        tape: _sage,
      ));
    }
    if (disputed != null && disputed.id != best?.id) {
      picks.add(_pickCard(
        label: _l('самый спорный', 'most divisive'),
        review: disputed,
        posters: posters,
        fonts: fonts,
        tilt: 0.03,
        tape: _coral,
      ));
    }

    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 44, 34, 40),
        buildBackground: (context) => _fullPage(_paintPaper),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_l('ваши вечера', 'your evenings').toUpperCase(),
              style: _t(fonts.bodyBold, 7.6, _inkFaint, ls: 2)),
          pw.SizedBox(height: 4),
          pw.Text(_l('в цифрах', 'at a glance'), style: _t(fonts.black, 28, _ink)),
          if (names.isNotEmpty || (first != null && last != null)) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              [
                if (names.isNotEmpty) names,
                if (first != null && last != null) '${_monthYear(first)} — ${_monthYear(last)}',
              ].join('  ·  '),
              style: _t(fonts.handBold, 17, _inkMuted),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              tile('${stats.evenings}', _l('вечеров вместе', 'evenings together'), _accent),
              pw.SizedBox(width: 10),
              tile(avg == null ? '—' : _num(avg), _l('средняя оценка', 'average score'), _pink),
              pw.SizedBox(width: 10),
              stats.sharedMoments > 0
                  ? tile('${stats.sharedMoments}', _l('общих моментов', 'shared moments'), _periwinkle)
                  : tile('${stats.unison}', _l('вечеров в унисон', 'evenings in unison'), _sage),
            ],
          ),
          if (verdictTotal > 0) ...[
            pw.SizedBox(height: 20),
            sectionLabel(_l('как совпадали ваши оценки', 'how your scores lined up')),
            pw.CustomPaint(
              size: const PdfPoint(_contentW, 12),
              painter: (c, s) {
                var x = 0.0;
                final parts = [
                  (stats.unison, _sage),
                  (stats.close, _mustard),
                  (stats.split, _coral),
                ];
                for (final (n, color) in parts) {
                  if (n == 0) continue;
                  final w = s.x * n / verdictTotal;
                  c.setFillColor(color);
                  _rr(c, x + 0.6, 0, math.max(w - 1.2, 1), s.y, 5);
                  c.fillPath();
                  x += w;
                }
              },
            ),
            pw.SizedBox(height: 7),
            pw.Row(children: [
              verdictLegend(_l('в унисон', 'in unison'), stats.unison, _sage),
              pw.SizedBox(width: 16),
              verdictLegend(_l('чуть по-разному', 'a little different'), stats.close, _mustard),
              pw.SizedBox(width: 16),
              verdictLegend(_l('спорные', 'divisive'), stats.split, _coral),
            ]),
          ],
          if (picks.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < picks.length; i++) ...[
                  if (i > 0) pw.SizedBox(width: 12),
                  pw.Expanded(child: picks[i]),
                ],
              ],
            ),
          ],
          if (stats.topTags.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            sectionLabel(_l('слова, к которым вы возвращались', 'the words you kept coming back to')),
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < stats.topTags.length; i++)
                  _pill(
                    stats.topTags[i].count > 1
                        ? '${pdfSafe(stats.topTags[i].tag)} · ${stats.topTags[i].count}'
                        : pdfSafe(stats.topTags[i].tag),
                    _personTones[i % _personTones.length],
                    fonts,
                    size: 7.4,
                  ),
              ],
            ),
          ],
          if (stats.perPerson.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            sectionLabel(_l('как оценивает каждый', 'how each of you scores')),
            for (final p in stats.perPerson)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(children: [
                  pw.Container(
                    width: 7,
                    height: 7,
                    decoration: pw.BoxDecoration(
                      color: tones[p.person.userId] ?? _accent,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(_nameOf(p.person.name),
                        maxLines: 1, style: _t(fonts.bodyBold, 9, _ink)),
                  ),
                  _hearts(p.average.round(), size: 8),
                  pw.SizedBox(width: 8),
                  pw.Text(_num(p.average), style: _t(fonts.black, 10, _ink)),
                  pw.SizedBox(width: 8),
                  pw.Text(_eveningsLabel(p.rated), style: _t(fonts.body, 7.6, _inkFaint)),
                ]),
              ),
          ],
          if (stats.momentEvenings > 0) ...[
            pw.SizedBox(height: 10),
            pw.Text(momentsSentence, style: _t(fonts.handBold, 15, _inkMuted)),
          ],
          pw.Spacer(),
          if (book.truncated)
            pw.Text(
              _l(
                'в книгу вошли последние ${_eveningsLabel(stats.evenings)} — самые давние остались за её страницами',
                'this book holds your latest ${_eveningsLabel(stats.evenings)} — the oldest ones stay outside its pages',
              ),
              style: _t(fonts.hand, 14, _inkFaint),
            ),
        ],
      ),
    );
  }

  /// "Best evening" / "most divisive" on the glance page: a polaroid and what
  /// made the evening that.
  static pw.Widget _pickCard({
    required String label,
    required CircleReview review,
    required Map<String, pw.MemoryImage> posters,
    required _Fonts fonts,
    required double tilt,
    required PdfColor tape,
  }) {
    final title = pdfSafe(review.title);
    final summary = review.summary;
    final avg = summary?.average;
    final spread = summary?.verdict == 'split' ? summary?.spread : null;
    final scoreText = spread == null ? _num(avg ?? 0) : '${_num(avg ?? 0)}  ·  ${_l('разброс', 'spread')} $spread';
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: pw.BoxDecoration(
        color: _paper,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _t(fonts.handBold, 17, _accent)),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(2, 4, 10, 4),
                child: _polaroidWidget(
                  posters: posters,
                  url: review.posterUrl,
                  title: title,
                  color: _mediaColor(review.mediaType),
                  width: 50,
                  height: 72,
                  fonts: fonts,
                  tilt: tilt,
                  tape: tape,
                  border: 3.4,
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(title.isEmpty ? '—' : title,
                        maxLines: 2, style: _t(fonts.display, 9.6, _ink, lh: 2)),
                    pw.SizedBox(height: 3),
                    pw.Text(_dayLabel(review.day), style: _t(fonts.body, 7.2, _inkMuted)),
                    if (avg != null) ...[
                      pw.SizedBox(height: 6),
                      _hearts(avg.round(), size: 5.6, gap: 1),
                      pw.SizedBox(height: 3),
                      pw.Text(scoreText, style: _t(fonts.black, 9, _ink)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- The evenings ---------------------------------------------------

  static pw.MultiPage _eveningsMultiPage({
    required List<CircleReview> reviews,
    required _Fonts fonts,
    required Map<String, pw.MemoryImage> posters,
    required Map<String, PdfColor> tones,
  }) {
    // `reviews` arrive oldest first; months keep that order.
    final months = <String, List<CircleReview>>{};
    for (final r in reviews) {
      months.putIfAbsent('${r.day.year}-${r.day.month}', () => []).add(r);
    }

    final children = <pw.Widget>[];
    var index = 0;
    for (final list in months.values) {
      final header = _monthHeader(list.first.day, list, fonts);
      final cards = <pw.Widget>[
        for (final r in list)
          _eveningCard(
            review: r,
            index: index++,
            posters: posters,
            tones: tones,
            fonts: fonts,
          ),
      ];
      // The month title travels with its first card, never stranded alone at
      // the bottom of a page.
      children.add(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [header, cards.first],
      ));
      children.addAll(cards.skip(1));
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

  static pw.Widget _monthHeader(DateTime month, List<CircleReview> list, _Fonts fonts) {
    // One bead per evening, colored by how warmly the evening was rated.
    final beads = list.take(46).toList();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_monthName(month.month), style: _t(fonts.black, 30, _ink)),
              pw.SizedBox(width: 10),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text('${month.year}', style: _t(fonts.handBold, 26, _accent)),
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
          pw.CustomPaint(
            size: const PdfPoint(_contentW, 8),
            painter: (c, s) {
              c.setStrokeColor(_border);
              c.setLineWidth(1);
              c.moveTo(0, 4);
              c.lineTo(s.x, 4);
              c.strokePath();
              var x = 0.0;
              for (final r in beads) {
                final avg = r.summary?.average;
                _fillCircle(c, avg == null ? _dot : _ratingColor(avg.round()), x + 4, 4, 3.6);
                x += 11;
              }
            },
          ),
        ],
      ),
    );
  }

  /// A person has something to print when they didn't skip and left a rating,
  /// a tag or a line that survives the fonts.
  static bool _hasSomethingToShow(ReviewPerson p) {
    if (p.skipped) return false;
    if (p.rating != null) return true;
    if (p.tags.any((t) => pdfSafe(t).isNotEmpty)) return true;
    return pdfSafe(p.line).isNotEmpty;
  }

  static String _nameOf(String raw) {
    final s = pdfSafe(raw);
    return s.isEmpty ? '…' : s;
  }

  /// Width of the card's text column: the content width less the card's
  /// padding, the polaroid and the gap beside it.
  static const double _cardTextW = _contentW - 28 - 69 - 16;

  static pw.Widget _eveningCard({
    required CircleReview review,
    required int index,
    required Map<String, pw.MemoryImage> posters,
    required Map<String, PdfColor> tones,
    required _Fonts fonts,
  }) {
    final summary = review.summary;
    final avg = summary?.average;
    final verdict = summary?.verdict ?? 'solo';
    final title = pdfSafe(review.title);
    final speakers = review.people.where(_hasSomethingToShow).toList();
    // A card must never be taller than a page — MultiPage refuses such a
    // widget outright — so the more voices there are, the less room each
    // gets: from four voices they sit in two columns, and past four their
    // lines and tags are cut shorter. (A circle holds at most four people;
    // the last step is only a guard.)
    final twoColumns = speakers.length > 3;
    final lineLimit = speakers.length > 4 ? 100 : (twoColumns ? 150 : 240);
    final tagLimit = twoColumns ? 4 : 6;
    final columnW = (_cardTextW - 14) / 2 - 1;
    final moments = _momentsBlock(review, fonts);

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _paper,
          borderRadius: pw.BorderRadius.circular(14),
          border: pw.Border.all(color: _border, width: 0.8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, left: 2, right: 14),
              child: _polaroidWidget(
                posters: posters,
                url: review.posterUrl,
                title: title,
                color: _mediaColor(review.mediaType),
                width: 58,
                height: 84,
                fonts: fonts,
                tilt: index.isEven ? -0.035 : 0.03,
                tape: _personTones[index % _personTones.length],
                border: 3.5,
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          title.isEmpty ? '—' : title,
                          maxLines: 2,
                          style: _t(fonts.display, 12, _ink, lh: 2.5),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      _pill(_typeLabel(review.mediaType), _mediaColor(review.mediaType), fonts),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    [
                      _dayLabel(review.day),
                      if (review.year != null) '${review.year}',
                    ].join('  ·  '),
                    style: _t(fonts.body, 7.6, _inkMuted),
                  ),
                  if (avg != null) ...[
                    pw.SizedBox(height: 9),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        _hearts(avg.round(), size: 8),
                        pw.SizedBox(width: 7),
                        pw.Text(_num(avg), style: _t(fonts.black, 13, _ink)),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Text(
                            verdictLine(verdict),
                            maxLines: 1,
                            style: _t(fonts.handBold, 14, _mix(_verdictColor(verdict), _ink, 0.25)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (speakers.isNotEmpty) ...[
                    pw.SizedBox(height: 9),
                    _dashedRule(_cardTextW - 4, _border),
                    pw.SizedBox(height: 9),
                  ],
                  if (twoColumns)
                    pw.Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        for (final person in speakers)
                          pw.SizedBox(
                            width: columnW,
                            child: _personBlock(person, tones[person.userId] ?? _accent, lineLimit, tagLimit, fonts),
                          ),
                      ],
                    )
                  else
                    for (var i = 0; i < speakers.length; i++) ...[
                      if (i > 0) pw.SizedBox(height: 10),
                      _personBlock(
                        speakers[i],
                        tones[speakers[i].userId] ?? _accent,
                        lineLimit,
                        tagLimit,
                        fonts,
                      ),
                    ],
                  if (moments != null) ...[
                    pw.SizedBox(height: 11),
                    _dashedRule(_cardTextW - 4, _border),
                    pw.SizedBox(height: 9),
                    moments,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One voice of the evening: who, how many hearts, their words, their line.
  static pw.Widget _personBlock(ReviewPerson p, PdfColor tone, int lineLimit, int tagLimit, _Fonts fonts) {
    final line = pdfClip(pdfSafe(p.line), lineLimit);
    final tags = [
      for (final t in p.tags)
        if (pdfSafe(t).isNotEmpty) pdfSafe(t),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 7,
              height: 7,
              decoration: pw.BoxDecoration(color: tone, shape: pw.BoxShape.circle),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Text(_nameOf(p.name), maxLines: 1, style: _t(fonts.bodyBold, 8.6, _ink)),
            ),
            if (p.rating != null) ...[
              _hearts(p.rating, size: 6.4, gap: 1.2, fill: tone),
              pw.SizedBox(width: 6),
              pw.Text('${p.rating}', style: _t(fonts.black, 10, _ink)),
            ],
          ],
        ),
        if (tags.isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final t in tags.take(tagLimit)) _pill(t, _mix(tone, _paper, 0.18), fonts, size: 6.2)],
          ),
        ],
        if (line.isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.only(left: 9),
            decoration: pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _mix(tone, _paper, 0.45), width: 2)),
            ),
            child: pw.Text(line, style: _t(fonts.hand, 14, _inkMuted, lh: 1.5)),
          ),
        ],
      ],
    );
  }

  /// The moments timeline of a room evening, or null for an evening without
  /// one (logged by hand, or a room nobody reacted in).
  static pw.Widget? _momentsBlock(CircleReview r, _Fonts fonts) {
    final moments = r.moments;
    if (moments == null || moments.isEmpty) return null;

    final last = moments.map((m) => m.positionMs).reduce(math.max);
    // The film's length isn't in the review; spread the moments over a
    // little more than the last one, with a floor so a single early moment
    // doesn't sit at the far end — the same rule as the on-screen timeline.
    final total = math.max(last * 1.1, 60000).toDouble();
    final shared = moments.where((m) => m.shared).toList()..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    const stripW = _cardTextW - 4;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_l('моменты', 'moments'), style: _t(fonts.handBold, 15, _accent)),
        pw.SizedBox(height: 5),
        pw.CustomPaint(
          size: const PdfPoint(stripW, 16),
          painter: (c, s) {
            c.setStrokeColor(_border);
            c.setLineWidth(1.2);
            c.moveTo(0, 8);
            c.lineTo(s.x, 8);
            c.strokePath();
            // Own moments first, shared on top so they are never hidden.
            for (final pass in [false, true]) {
              for (final m in moments.where((x) => x.shared == pass)) {
                final x = (m.positionMs / total * (s.x - 10)).clamp(0.0, s.x - 10).toDouble() + 5;
                if (pass) {
                  _fillCircle(c, _pink, x, 8, 5.2);
                  _fillCircle(c, _paper, x, 8, 2.2);
                } else {
                  _fillCircle(c, _sage, x, 8, 3);
                }
              }
            }
          },
        ),
        pw.SizedBox(height: 6),
        if (shared.isEmpty)
          pw.Text(
            _l('каждый реагировал в своих местах', 'each of you reacted in your own places'),
            style: _t(fonts.hand, 13.5, _inkFaint),
          )
        else ...[
          for (final m in shared.take(3))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(children: [
                pw.SizedBox(
                  width: 44,
                  child: pw.Text(clockLabel(m.positionMs), style: _t(fonts.bodyBold, 8, _pink)),
                ),
                pw.Expanded(
                  child: pw.Text(
                    '${_l('вы вместе', 'together')}: ${pdfSafe(emotionLabel(m.top))}',
                    maxLines: 1,
                    style: _t(fonts.hand, 14, _ink),
                  ),
                ),
              ]),
            ),
          if (shared.length > 3)
            pw.Text(
              _l('и ещё ${shared.length - 3}', 'and ${shared.length - 3} more'),
              style: _t(fonts.hand, 13, _inkFaint),
            ),
        ],
      ],
    );
  }

  // ---- Back cover -----------------------------------------------------

  static pw.Page _closingPage({required _Fonts fonts, required pw.MemoryImage? mascot}) {
    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (context) => _fullPage((c, s) => _paintCover(c, s, 11)),
      ),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            _mascotRing(mascot, 70, _foil),
            pw.SizedBox(height: 26),
            pw.Text(
              _l('впереди ещё\nмного вечеров', 'many more evenings\nahead of you'),
              textAlign: pw.TextAlign.center,
              style: _t(fonts.black, 21, _cream, lh: 6),
            ),
            pw.SizedBox(height: 16),
            _ornament(150, _foil),
            pw.SizedBox(height: 18),
            pw.Text(_spaced(_brand), style: _t(fonts.bodyBold, 9, _foil, ls: 3)),
          ],
        ),
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
