import '../room_strings.dart';

/// Copy for reading together. Same register as the rest of the room: all
/// lowercase, warm, Russian first with an English twin (see room_strings.dart).

String placeLabel({required bool comic, required int major, int? units}) {
  if (comic) {
    final total = (units != null && units > 0) ? ' ${at('из', 'of')} $units' : '';
    return at('стр. ${major + 1}$total', 'page ${major + 1}$total');
  }
  final total = (units != null && units > 0) ? ' ${at('из', 'of')} $units' : '';
  return at('глава ${major + 1}$total', 'chapter ${major + 1}$total');
}

/// "глава 4 · 31%"
String peerPlace({required bool comic, required int major, required int progress, int? units}) {
  final base = placeLabel(comic: comic, major: major, units: units);
  return progress > 0 ? '$base · ${(progress / 10).round()}%' : base;
}

String openErrorText(String code) => switch (code) {
      'drm' => at(
          'эта книга защищена от копирования — такую открыть не получится. подойдёт файл без защиты (drm)',
          'this book is copy-protected, so it can’t be opened here. a file without drm will work'),
      'empty' => at('в этом файле не нашлось текста или страниц', 'there’s no text or pages in this file'),
      'missing' => at('файл не нашёлся — выберите его ещё раз', 'the file isn’t there — choose it again'),
      _ => at('не получилось открыть файл — похоже, он повреждён', 'couldn’t open the file — it looks damaged'),
    };

const readingTextSizes = <double>[15, 17, 19, 22];
