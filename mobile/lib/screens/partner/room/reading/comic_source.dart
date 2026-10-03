import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

import 'book_source.dart' show BookOpenException, fileSha256;

/// A person's own comic archive (CBZ, or a ZIP of images), opened on their own
/// device. Like a book (see book_source.dart) it is never uploaded or relayed:
/// the room only learns the file's fingerprint and which page everybody is on.
///
/// Pages are read from the archive on demand and a few are kept around, so a
/// two-hundred-page volume never sits in memory all at once. The page order is
/// a *natural* sort of the file names ("2.jpg" before "10.jpg"), which is what
/// keeps "page 42" the same page on every phone holding the same archive.
class ComicArchive {
  ComicArchive._(this.path, this.hash, this._input, this._pages);

  final String path;
  final String hash;
  final InputFileStream _input;
  final List<ArchiveFile> _pages;

  int get pageCount => _pages.length;

  static const _keep = 8;
  final Map<int, Uint8List> _cache = {};
  final List<int> _order = [];

  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

  static Future<ComicArchive> open(String path) async {
    final file = File(path);
    if (!await file.exists()) throw const BookOpenException('missing');
    final hash = await fileSha256(path);
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final pages = <ArchiveFile>[
        for (final f in archive)
          if (f.isFile && _isPage(f.name)) f,
      ];
      pages.sort((a, b) => _naturalCompare(a.name.toLowerCase(), b.name.toLowerCase()));
      if (pages.isEmpty) {
        await input.close();
        throw const BookOpenException('empty');
      }
      return ComicArchive._(path, hash, input, pages);
    } on BookOpenException {
      rethrow;
    } catch (_) {
      await input.close();
      throw const BookOpenException('broken');
    }
  }

  static bool _isPage(String name) {
    final n = name.replaceAll('\\', '/');
    if (n.startsWith('__MACOSX/') || n.split('/').any((p) => p.startsWith('.'))) return false;
    final dot = n.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExtensions.contains(n.substring(dot).toLowerCase());
  }

  /// "page2" < "page10": digit runs compare as numbers.
  static int _naturalCompare(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
    final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
    final n = pa.length < pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = pa[i];
      final y = pb[i];
      final nx = int.tryParse(x);
      final ny = int.tryParse(y);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  /// The bytes of one page (0-based), from the cache when it is there.
  Uint8List page(int index) {
    final i = index.clamp(0, _pages.length - 1);
    final hit = _cache[i];
    if (hit != null) {
      _order
        ..remove(i)
        ..add(i);
      return hit;
    }
    // archive 4.x: readBytes() is Uint8List? — an unreadable page comes back
    // empty (and isn't cached) rather than crashing the reader.
    final bytes = _pages[i].readBytes();
    if (bytes == null) return Uint8List(0);
    _cache[i] = bytes;
    _order.add(i);
    while (_order.length > _keep) {
      _cache.remove(_order.removeAt(0));
    }
    return bytes;
  }

  Future<void> dispose() async {
    _cache.clear();
    _order.clear();
    try {
      await _input.close();
    } catch (_) {}
  }
}
