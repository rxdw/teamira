import '../services/locale_service.dart';

/// Mirrors `TitleExtras` and its parts in backend/app/schemas.py — the richer,
/// per-type layer of the title screen for games, books, manga and anime
/// (screenshots, authors, characters, languages, where to play/read/buy,
/// related works ...). One nested object on [MediaItem.extras] rather than ~30
/// new top-level fields; null on every search/feed card, set by
/// GET /media/detail only.
///
/// Every list defaults to empty and every scalar to null: "unknown", never a
/// made-up value. The widgets in screens/title/title_extras_sections.dart hide
/// themselves when their slice is empty, so a title nobody had extras for just
/// looks like it always did.

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) =>
    (raw as List? ?? const [])
        .whereType<Map>()
        .map((e) => parse(Map<String, dynamic>.from(e)))
        .toList();

class TitleTag {
  final String name;
  final int? rank; // 0-100 community agreement (AniList); null for plain tags
  const TitleTag({required this.name, this.rank});

  factory TitleTag.fromJson(Map<String, dynamic> j) =>
      TitleTag(name: (j['name'] ?? '').toString(), rank: (j['rank'] as num?)?.toInt());
}

class GameLanguage {
  final String name; // English name; translated at display time
  final bool interface;
  final bool audio;
  final bool subtitles;
  const GameLanguage({
    required this.name,
    this.interface = false,
    this.audio = false,
    this.subtitles = false,
  });

  bool get isRussian => name.toLowerCase().startsWith('russian') || name.toLowerCase() == 'русский';

  factory GameLanguage.fromJson(Map<String, dynamic> j) => GameLanguage(
        name: (j['name'] ?? '').toString(),
        interface: j['interface'] == true,
        audio: j['audio'] == true,
        subtitles: j['subtitles'] == true,
      );
}

class TimeToBeat {
  final double? hastily;
  final double? normally;
  final double? completely;
  final int? votes;
  const TimeToBeat({this.hastily, this.normally, this.completely, this.votes});

  bool get isEmpty => hastily == null && normally == null && completely == null;

  factory TimeToBeat.fromJson(Map<String, dynamic> j) => TimeToBeat(
        hastily: (j['hastily'] as num?)?.toDouble(),
        normally: (j['normally'] as num?)?.toDouble(),
        completely: (j['completely'] as num?)?.toDouble(),
        votes: (j['votes'] as num?)?.toInt(),
      );
}

class TitleLink {
  /// official | steam | gog | epic | playstation | xbox | nintendo | itch |
  /// store | read | preview | buy | wiki | other — picks the icon.
  final String kind;
  final String label; // English; "Official site" etc. are translated, brands are not
  final String url;
  const TitleLink({required this.kind, required this.label, required this.url});

  factory TitleLink.fromJson(Map<String, dynamic> j) => TitleLink(
        kind: (j['kind'] ?? 'other').toString(),
        label: (j['label'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
      );
}

/// A person behind the work (book/manga author, anime staff). Not a TMDB
/// person, so — unlike CastMember — never opens a person screen.
class TitleCreator {
  final String name;
  final String? nameRu;
  final String? role; // "Author" | "Story" | "Art" | "Story & Art" | "Director" ...
  final String? photoUrl;
  final String? bio;
  final String? born;
  const TitleCreator({required this.name, this.nameRu, this.role, this.photoUrl, this.bio, this.born});

  /// Cyrillic name when the device shows Russian content and Shikimori had
  /// one; the romanised/original name otherwise.
  String get displayName =>
      (LocaleService.contentPrefersRussian && (nameRu?.isNotEmpty ?? false)) ? nameRu! : name;

  factory TitleCreator.fromJson(Map<String, dynamic> j) => TitleCreator(
        name: (j['name'] ?? '').toString(),
        nameRu: _str(j['name_ru']),
        role: _str(j['role']),
        photoUrl: _str(j['photo_url']),
        bio: _str(j['bio']),
        born: _str(j['born']),
      );
}

class TitleCharacter {
  final String name;
  final String? nameRu;
  final String? role; // "Main" | "Supporting"
  final String? photoUrl;
  const TitleCharacter({required this.name, this.nameRu, this.role, this.photoUrl});

  String get displayName =>
      (LocaleService.contentPrefersRussian && (nameRu?.isNotEmpty ?? false)) ? nameRu! : name;

  factory TitleCharacter.fromJson(Map<String, dynamic> j) => TitleCharacter(
        name: (j['name'] ?? '').toString(),
        nameRu: _str(j['name_ru']),
        role: _str(j['role']),
        photoUrl: _str(j['photo_url']),
      );
}

/// Another work connected to this one. With [id]+[source] it opens directly;
/// without (a manga's anime adaptation) the client searches by title.
class RelatedTitle {
  final String relation; // English key: "Adaptation", "Sequel", "DLC", "Same series" ...
  final String title;
  final String? titleRu;
  final String mediaType;
  final int? year;
  final String? posterUrl;
  final String? id;
  final String? source;
  const RelatedTitle({
    required this.relation,
    required this.title,
    this.titleRu,
    required this.mediaType,
    this.year,
    this.posterUrl,
    this.id,
    this.source,
  });

  bool get canOpenDirectly => id != null && source != null;

  String get displayTitle =>
      (LocaleService.contentPrefersRussian && (titleRu?.isNotEmpty ?? false)) ? titleRu! : title;

  factory RelatedTitle.fromJson(Map<String, dynamic> j) => RelatedTitle(
        relation: (j['relation'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        titleRu: _str(j['title_ru']),
        mediaType: (j['media_type'] ?? '').toString(),
        year: (j['year'] as num?)?.toInt(),
        posterUrl: _str(j['poster_url']),
        id: _str(j['id']),
        source: _str(j['source']),
      );
}

class ReadingLog {
  final int? want;
  final int? reading;
  final int? read;
  const ReadingLog({this.want, this.reading, this.read});

  bool get isEmpty => (want ?? 0) == 0 && (reading ?? 0) == 0 && (read ?? 0) == 0;

  factory ReadingLog.fromJson(Map<String, dynamic> j) => ReadingLog(
        want: (j['want'] as num?)?.toInt(),
        reading: (j['reading'] as num?)?.toInt(),
        read: (j['read'] as num?)?.toInt(),
      );
}

/// One line of a PC system-requirements list ("Memory" / "8 GB RAM").
class SpecRow {
  final String label; // canonical English ("OS", "Graphics" ...) or empty
  final String value;
  const SpecRow({this.label = '', required this.value});

  factory SpecRow.fromJson(Map<String, dynamic> j) =>
      SpecRow(label: (j['label'] ?? '').toString(), value: (j['value'] ?? '').toString());
}

class SystemRequirements {
  final List<SpecRow> minimum;
  final List<SpecRow> recommended;
  const SystemRequirements({this.minimum = const [], this.recommended = const []});

  bool get isEmpty => minimum.isEmpty && recommended.isEmpty;

  factory SystemRequirements.fromJson(Map<String, dynamic> j) => SystemRequirements(
        minimum: _list(j['minimum'], SpecRow.fromJson).where((r) => r.value.isNotEmpty).toList(),
        recommended: _list(j['recommended'], SpecRow.fromJson).where((r) => r.value.isNotEmpty).toList(),
      );
}

class TitleExtras {
  // shared
  final List<String> screenshots;
  final List<TitleTag> tags;
  final List<TitleLink> links;
  final List<RelatedTitle> related;
  final List<String> altTitles;
  final String? originalLanguage;
  final int? popularity;
  final int? favourites;

  // games
  final String? storyline;
  final List<String> perspectives;
  final List<GameLanguage> languages;
  final TimeToBeat? timeToBeat;
  final String? price;
  final int? priceDiscountPct;
  final bool? freeToPlay;
  final int? metacritic;
  final int? achievements;
  final List<String> steamFeatures;
  final SystemRequirements? requirements;
  final List<String> pcPlatforms; // windows | mac | linux
  final String? steamDeck; // verified | playable | unsupported
  final int? criticScore;
  final int? criticVotes;

  // books
  final int? pages;
  final String? publishedDate;
  final String? subtitle;
  final String? bookLanguage;
  final List<TitleCreator> creators; // also manga authors / anime staff
  final String? firstSentence;
  final ReadingLog? readingLog;

  // manga / anime
  final List<TitleCharacter> characters;
  final List<String> studios;
  final String? sourceMaterial;
  final int? episodes;
  final int? episodesAired;
  final int? episodeMinutes;
  final String? nextEpisodeAt;
  final String? startDate;
  final String? endDate;

  const TitleExtras({
    this.screenshots = const [],
    this.tags = const [],
    this.links = const [],
    this.related = const [],
    this.altTitles = const [],
    this.originalLanguage,
    this.popularity,
    this.favourites,
    this.storyline,
    this.perspectives = const [],
    this.languages = const [],
    this.timeToBeat,
    this.price,
    this.priceDiscountPct,
    this.freeToPlay,
    this.metacritic,
    this.achievements,
    this.steamFeatures = const [],
    this.requirements,
    this.pcPlatforms = const [],
    this.steamDeck,
    this.criticScore,
    this.criticVotes,
    this.pages,
    this.publishedDate,
    this.subtitle,
    this.bookLanguage,
    this.creators = const [],
    this.firstSentence,
    this.readingLog,
    this.characters = const [],
    this.studios = const [],
    this.sourceMaterial,
    this.episodes,
    this.episodesAired,
    this.episodeMinutes,
    this.nextEpisodeAt,
    this.startDate,
    this.endDate,
  });

  factory TitleExtras.fromJson(Map<String, dynamic> j) {
    final ttb = j['time_to_beat'];
    final log = j['reading_log'];
    final reqs = j['requirements'];
    return TitleExtras(
      screenshots: (j['screenshots'] as List? ?? const []).map((e) => e.toString()).toList(),
      tags: _list(j['tags'], TitleTag.fromJson).where((t) => t.name.isNotEmpty).toList(),
      links: _list(j['links'], TitleLink.fromJson).where((l) => l.url.startsWith('http')).toList(),
      related: _list(j['related'], RelatedTitle.fromJson).where((r) => r.title.isNotEmpty).toList(),
      altTitles: (j['alt_titles'] as List? ?? const []).map((e) => e.toString()).toList(),
      originalLanguage: _str(j['original_language']),
      popularity: (j['popularity'] as num?)?.toInt(),
      favourites: (j['favourites'] as num?)?.toInt(),
      storyline: _str(j['storyline']),
      perspectives: (j['perspectives'] as List? ?? const []).map((e) => e.toString()).toList(),
      languages: _list(j['languages'], GameLanguage.fromJson),
      timeToBeat: ttb is Map ? TimeToBeat.fromJson(Map<String, dynamic>.from(ttb)) : null,
      price: _str(j['price']),
      priceDiscountPct: (j['price_discount_pct'] as num?)?.toInt(),
      freeToPlay: j['free_to_play'] as bool?,
      metacritic: (j['metacritic'] as num?)?.toInt(),
      achievements: (j['achievements'] as num?)?.toInt(),
      steamFeatures: (j['steam_features'] as List? ?? const []).map((e) => e.toString()).toList(),
      requirements: reqs is Map ? SystemRequirements.fromJson(Map<String, dynamic>.from(reqs)) : null,
      pcPlatforms: (j['pc_platforms'] as List? ?? const []).map((e) => e.toString()).toList(),
      steamDeck: _str(j['steam_deck']),
      criticScore: (j['critic_score'] as num?)?.toInt(),
      criticVotes: (j['critic_votes'] as num?)?.toInt(),
      pages: (j['pages'] as num?)?.toInt(),
      publishedDate: _str(j['published_date']),
      subtitle: _str(j['subtitle']),
      bookLanguage: _str(j['book_language']),
      creators: _list(j['creators'], TitleCreator.fromJson).where((c) => c.name.isNotEmpty).toList(),
      firstSentence: _str(j['first_sentence']),
      readingLog: log is Map ? ReadingLog.fromJson(Map<String, dynamic>.from(log)) : null,
      characters: _list(j['characters'], TitleCharacter.fromJson).where((c) => c.name.isNotEmpty).toList(),
      studios: (j['studios'] as List? ?? const []).map((e) => e.toString()).toList(),
      sourceMaterial: _str(j['source_material']),
      episodes: (j['episodes'] as num?)?.toInt(),
      episodesAired: (j['episodes_aired'] as num?)?.toInt(),
      episodeMinutes: (j['episode_minutes'] as num?)?.toInt(),
      nextEpisodeAt: _str(j['next_episode_at']),
      startDate: _str(j['start_date']),
      endDate: _str(j['end_date']),
    );
  }
}
