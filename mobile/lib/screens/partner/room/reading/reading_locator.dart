import '../../../../models/co_view_room.dart';

/// A place in a book or manga, spelled the way the server spells it
/// (backend/app/co_reading.py) so "the same place" is the same string on
/// every device:
///
///   epub      c{chapter}:p{paragraph}   both 0-based
///   cbz       p{page}                    0-based page of the archive
///   parallel  c{chapter}                 0-based counter for something read
///                                        elsewhere (the screen shows +1)
///
/// Pages of a book are different on every screen (font, size, margins), so a
/// place in a book is "chapter + paragraph", which is the same for the same
/// file everywhere.
class ReadLocator implements Comparable<ReadLocator> {
  final ReadKind kind;

  /// The chapter (EPUB, parallel) or the page (comic).
  final int major;

  /// The paragraph inside the chapter (EPUB); always 0 for the others.
  final int minor;

  const ReadLocator(this.kind, this.major, [this.minor = 0]);

  static const int maxChapter = 9999;
  static const int maxParagraph = 99999;
  static const int maxPage = 99999;

  static ReadLocator start(ReadKind kind) => ReadLocator(kind, 0, 0);

  String get wire => switch (kind) {
        ReadKind.epub => 'c$major:p$minor',
        ReadKind.cbz => 'p$major',
        ReadKind.parallel => 'c$major',
      };

  static final RegExp _epub = RegExp(r'^c(\d{1,4})(?::p(\d{1,5}))?$');
  static final RegExp _cbz = RegExp(r'^p(\d{1,5})$');
  static final RegExp _parallel = RegExp(r'^c(\d{1,4})$');

  /// Null for anything the server would not accept for this kind.
  static ReadLocator? tryParse(ReadKind kind, String? raw) {
    final text = (raw ?? '').trim().toLowerCase();
    switch (kind) {
      case ReadKind.epub:
        final m = _epub.firstMatch(text);
        if (m == null) return null;
        return ReadLocator(kind, int.parse(m.group(1)!), int.parse(m.group(2) ?? '0'));
      case ReadKind.cbz:
        final m = _cbz.firstMatch(text);
        if (m == null) return null;
        return ReadLocator(kind, int.parse(m.group(1)!));
      case ReadKind.parallel:
        final m = _parallel.firstMatch(text);
        if (m == null) return null;
        return ReadLocator(kind, int.parse(m.group(1)!));
    }
  }

  @override
  int compareTo(ReadLocator other) {
    final c = major.compareTo(other.major);
    return c != 0 ? c : minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is ReadLocator && other.kind == kind && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(kind, major, minor);

  @override
  String toString() => wire;
}

/// A permille (0..1000) of the way through, which is what the room keeps and
/// draws. Only the device knows how long the book is, so it works this out.
int permille(double fraction) => (fraction.clamp(0.0, 1.0) * 1000).round();

/// The permille as a whole percent for a label.
int percentOf(int permilleValue) => (permilleValue / 10).round().clamp(0, 100);
