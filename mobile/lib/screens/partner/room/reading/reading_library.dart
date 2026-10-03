import 'package:shared_preferences/shared_preferences.dart';

import 'book_source.dart';
import 'comic_source.dart';

/// What this device remembers about reading together — all of it local and
/// none of it the text itself:
///
///  * where a file lives, by its fingerprint, so coming back to a room opens
///    your copy by itself instead of asking for the file again;
///  * where you stopped in it, so a room you left carries on from your page;
///  * how you like to read (text size, manga right-to-left);
///  * a file that was just opened to start a room, handed to the room screen
///    so it doesn't read the same archive twice.
class ReadingLibrary {
  ReadingLibrary._();
  static final ReadingLibrary instance = ReadingLibrary._();

  static const _pathPrefix = 'seenly_read_path_';
  static const _placePrefix = 'seenly_read_place_';
  static const _sizeKey = 'seenly_read_text_size';
  static const _rtlKey = 'seenly_read_manga_rtl';

  LocalBook? _preparedBook;
  ComicArchive? _preparedComic;

  /// Keeps an already-opened file for the room that is about to open.
  void prepare({LocalBook? book, ComicArchive? comic}) {
    _preparedBook = book;
    _preparedComic = comic;
  }

  LocalBook? takePreparedBook(String hash) {
    final b = _preparedBook;
    if (b != null && b.hash == hash) {
      _preparedBook = null;
      return b;
    }
    return null;
  }

  ComicArchive? takePreparedComic(String hash) {
    final c = _preparedComic;
    if (c != null && c.hash == hash) {
      _preparedComic = null;
      return c;
    }
    return null;
  }

  Future<String?> pathFor(String hash) async =>
      (await SharedPreferences.getInstance()).getString('$_pathPrefix$hash');

  Future<void> rememberPath(String hash, String path) async =>
      (await SharedPreferences.getInstance()).setString('$_pathPrefix$hash', path);

  Future<void> forgetPath(String hash) async =>
      (await SharedPreferences.getInstance()).remove('$_pathPrefix$hash');

  Future<String?> savedPlace(String hash) async =>
      (await SharedPreferences.getInstance()).getString('$_placePrefix$hash');

  Future<void> savePlace(String hash, String locator) async =>
      (await SharedPreferences.getInstance()).setString('$_placePrefix$hash', locator);

  /// Index into `readingTextSizes`.
  Future<int> textSize() async => (await SharedPreferences.getInstance()).getInt(_sizeKey) ?? 1;

  Future<void> setTextSize(int index) async =>
      (await SharedPreferences.getInstance()).setInt(_sizeKey, index);

  Future<bool> mangaRtl() async => (await SharedPreferences.getInstance()).getBool(_rtlKey) ?? true;

  Future<void> setMangaRtl(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_rtlKey, value);
}
