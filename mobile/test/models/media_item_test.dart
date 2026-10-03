// Unit tests for models/media_item.dart.
//
// These cover the pure parsing/display logic that every screen relies on
// indirectly (search results, feed, diary, co-viewing decks all flow
// through MediaItem.fromJson). No widget pumping needed — this is plain
// JSON-in/object-out plus a couple of getters that read the app-wide
// [LocaleService.contentPrefersRussian] static flag.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/media_item.dart';
import 'package:teamira/services/locale_service.dart';

void main() {
  // LocalizedText.display and MediaItem.posterUrl both read this static
  // flag directly (see locale_service.dart's own docstring on why it's
  // static). Reset it around every test so one test's locale choice can
  // never leak into the next.
  setUp(() {
    LocaleService.contentPrefersRussian = false;
  });
  tearDown(() {
    LocaleService.contentPrefersRussian = false;
  });

  group('LocalizedText.display', () {
    test('prefers English when device does not prefer Russian', () {
      const text = LocalizedText(ru: 'Матрица', en: 'The Matrix');
      LocaleService.contentPrefersRussian = false;
      expect(text.display, 'The Matrix');
    });

    test('prefers Russian when device prefers Russian and it exists', () {
      const text = LocalizedText(ru: 'Матрица', en: 'The Matrix');
      LocaleService.contentPrefersRussian = true;
      expect(text.display, 'Матрица');
    });

    test('falls back to the other language when the preferred one is null',
        () {
      const text = LocalizedText(ru: null, en: 'The Matrix');
      LocaleService.contentPrefersRussian = true;
      expect(text.display, 'The Matrix');
    });

    test('falls back to the other language when the preferred one is blank',
        () {
      // Whitespace-only counts as "no content" too — a title synced from
      // a source that sent an empty-but-present string shouldn't win over
      // a real translation in the other language.
      const text = LocalizedText(ru: '   ', en: 'The Matrix');
      LocaleService.contentPrefersRussian = true;
      expect(text.display, 'The Matrix');
    });

    test('renders the em-dash placeholder when both languages are empty',
        () {
      const text = LocalizedText(ru: null, en: null);
      expect(text.display, '—');
    });
  });

  group('ExternalIds', () {
    test('round-trips through fromJson/toJson', () {
      final ids = ExternalIds.fromJson({'tmdb': '603', 'imdb': 'tt0133093'});
      expect(ids.tmdb, '603');
      expect(ids.imdb, 'tt0133093');
      expect(ids.toJson(), {'tmdb': '603', 'imdb': 'tt0133093'});
    });

    test('tolerates missing keys', () {
      final ids = ExternalIds.fromJson({});
      expect(ids.tmdb, isNull);
      expect(ids.imdb, isNull);
    });
  });

  group('CastMember.fromJson', () {
    test('parses a full row, including the localized character name', () {
      final member = CastMember.fromJson({
        'person_id': '6384',
        'name': 'Keanu Reeves',
        'character': {'ru': 'Нео', 'en': 'Neo'},
        'photo_url': 'https://example.com/keanu.jpg',
      });
      expect(member.personId, '6384');
      expect(member.name, 'Keanu Reeves');
      expect(member.character?.en, 'Neo');
      expect(member.character?.ru, 'Нео');
      expect(member.photoUrl, 'https://example.com/keanu.jpg');
    });

    test('character is null when the source has none for this credit', () {
      final member = CastMember.fromJson({
        'person_id': null,
        'name': 'Extra',
        'character': null,
        'photo_url': null,
      });
      expect(member.character, isNull);
    });
  });

  Map<String, dynamic> _fullMovieJson() => {
        'id': '603',
        'media_type': 'movie',
        'external_ids': {'tmdb': '603', 'imdb': 'tt0133093'},
        'title': {'ru': 'Матрица', 'en': 'The Matrix'},
        'description': {'ru': 'Описание', 'en': 'Description'},
        'poster_url': 'https://image.tmdb.org/poster.jpg',
        'poster_url_ru': 'https://api.example.com/media/image-proxy?ru',
        'backdrop_url': 'https://image.tmdb.org/backdrop.jpg',
        'year': 1999,
        'genres': ['Sci-Fi', 'Action'],
        'rating': 8.7,
        'source': 'tmdb',
        'runtime_minutes': 136,
        'director': 'Lana Wachowski',
        'director_id': '9339',
        'cast': [
          {'person_id': '6384', 'name': 'Keanu Reeves', 'character': null, 'photo_url': null},
        ],
      };

  group('MediaItem.fromJson', () {
    test('parses every field present in a full detail response', () {
      final item = MediaItem.fromJson(_fullMovieJson());

      expect(item.id, '603');
      expect(item.mediaType, 'movie');
      expect(item.year, 1999);
      expect(item.genres, ['Sci-Fi', 'Action']);
      // JSON numbers can come back as int or double — rating must always
      // end up a double regardless of which one the backend sent.
      expect(item.rating, 8.7);
      expect(item.source, 'tmdb');
      expect(item.runtimeMinutes, 136);
      expect(item.director, 'Lana Wachowski');
      expect(item.cast, hasLength(1));
      expect(item.cast.single.name, 'Keanu Reeves');
    });

    test('tolerates a minimal search-result-shaped payload', () {
      // GET /media/search never sends cast/director/tagline/etc — every
      // one of those fields must default to null/empty rather than throw.
      final item = MediaItem.fromJson({
        'id': '603',
        'media_type': 'movie',
        'title': {'en': 'The Matrix'},
        // Explicit type args: a bare `{}` here would infer as
        // Map<dynamic, dynamic> rather than Map<String, dynamic> (the
        // slot's static type is `dynamic`, so there's no downward
        // context to infer from), which then fails the `as
        // Map<String, dynamic>?` cast inside MediaItem.fromJson.
        'description': <String, dynamic>{},
        'source': 'tmdb',
      });
      expect(item.externalIds.tmdb, isNull);
      expect(item.genres, isEmpty);
      expect(item.cast, isEmpty);
      expect(item.director, isNull);
      expect(item.rating, isNull);
    });

    test('genres/platforms/game_modes coerce every element to String', () {
      // Defends against a backend list that comes back with a non-string
      // element (an id where a label was expected, a stray number) —
      // .toString() coercion must keep this from throwing a type-cast
      // error while parsing an otherwise-fine catalog response.
      final item = MediaItem.fromJson({
        'id': '1',
        'media_type': 'game',
        'title': {'en': 'Some Game'},
        'description': <String, dynamic>{},
        'source': 'igdb',
        'genres': ['Action', 42],
        'platforms': ['PC', 5],
        'game_modes': ['Co-op'],
      });
      expect(item.genres, ['Action', '42']);
      expect(item.platforms, ['PC', '5']);
      expect(item.gameModes, ['Co-op']);
    });
  });

  group('MediaItem.posterUrl', () {
    test('uses the base poster when the device does not prefer Russian', () {
      final item = MediaItem.fromJson(_fullMovieJson());
      LocaleService.contentPrefersRussian = false;
      expect(item.posterUrl, 'https://image.tmdb.org/poster.jpg');
      // The non-Russian poster must stay reachable as the load-failure
      // fallback regardless of which one posterUrl itself is showing.
      expect(item.posterUrlFallback, 'https://image.tmdb.org/poster.jpg');
    });

    test('prefers the Russian poster when the device prefers Russian and TMDB has one',
        () {
      final item = MediaItem.fromJson(_fullMovieJson());
      LocaleService.contentPrefersRussian = true;
      expect(item.posterUrl, 'https://api.example.com/media/image-proxy?ru');
      // The base poster is still available as the fallback even while RU
      // is the one actually showing.
      expect(item.posterUrlFallback, 'https://image.tmdb.org/poster.jpg');
    });

    test('falls back to the base poster when device prefers Russian but TMDB has none',
        () {
      final json = _fullMovieJson()..remove('poster_url_ru');
      final item = MediaItem.fromJson(json);
      LocaleService.contentPrefersRussian = true;
      expect(item.posterUrl, 'https://image.tmdb.org/poster.jpg');
    });
  });

  group('MediaItem.toJson', () {
    test('only sends the fields the backend actually reads back', () {
      // Deliberate asymmetry with fromJson (see the field's own comment
      // in media_item.dart): poster_url_ru, cast, director, tagline etc.
      // are server-populated read-only data and must NOT round-trip back
      // out, or a client could overwrite server-derived fields it has no
      // business setting.
      final item = MediaItem.fromJson(_fullMovieJson());
      final out = item.toJson();

      expect(out.keys, containsAll([
        'id', 'media_type', 'external_ids', 'title', 'description',
        'poster_url', 'backdrop_url', 'year', 'genres', 'rating', 'source',
        'runtime_minutes',
      ]));
      expect(out.containsKey('poster_url_ru'), isFalse);
      expect(out.containsKey('cast'), isFalse);
      expect(out.containsKey('director'), isFalse);
      // toJson always sends the *base* poster, never the currently-
      // displayed (possibly Russian) one — the backend's own poster_url
      // column has never meant "whichever language the client happened
      // to be showing".
      LocaleService.contentPrefersRussian = true;
      expect(item.toJson()['poster_url'], 'https://image.tmdb.org/poster.jpg');
    });
  });
}
