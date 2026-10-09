/// Where the user is in one book or manga — mirrors
/// backend ReadingProgressOut (routers/progress.py, GET/PUT /progress/reading).
/// Each counter is null when that one isn't being tracked; a bookmark with all
/// three null is the same as "not started".
class ReadingBookmark {
  final int? volume;
  final int? chapter;
  final int? page;
  const ReadingBookmark({this.volume, this.chapter, this.page});

  static const empty = ReadingBookmark();

  bool get isEmpty => (volume ?? 0) == 0 && (chapter ?? 0) == 0 && (page ?? 0) == 0;

  ReadingBookmark copyWith({
    int? volume,
    int? chapter,
    int? page,
    bool clearVolume = false,
    bool clearChapter = false,
    bool clearPage = false,
  }) =>
      ReadingBookmark(
        volume: clearVolume ? null : (volume ?? this.volume),
        chapter: clearChapter ? null : (chapter ?? this.chapter),
        page: clearPage ? null : (page ?? this.page),
      );

  factory ReadingBookmark.fromJson(Map<String, dynamic> j) => ReadingBookmark(
        volume: (j['volume'] as num?)?.toInt(),
        chapter: (j['chapter'] as num?)?.toInt(),
        page: (j['page'] as num?)?.toInt(),
      );
}
