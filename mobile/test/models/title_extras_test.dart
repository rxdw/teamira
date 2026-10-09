// Unit tests for models/title_extras.dart — the client side of
// backend/app/schemas.py::TitleExtras. The detail screen's sections hide
// themselves on empty data, so the contract that matters is: an absent or
// partial `extras` object must parse to "nothing to show", never throw, and a
// full one must come through intact.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/media_item.dart';
import 'package:teamira/models/title_extras.dart';

Map<String, dynamic> _item(Map<String, dynamic>? extras) => {
      'id': 'igdb-1',
      'media_type': 'game',
      'title': {'en': 'Portal 2'},
      'description': <String, dynamic>{},
      'source': 'igdb',
      if (extras != null) 'extras': extras,
    };

void main() {
  group('MediaItem.extras', () {
    test('is null on a card without extras (search, shelves)', () {
      expect(MediaItem.fromJson(_item(null)).extras, isNull);
    });

    test('an empty object parses to an empty TitleExtras', () {
      final x = MediaItem.fromJson(_item(<String, dynamic>{})).extras!;
      expect(x.screenshots, isEmpty);
      expect(x.creators, isEmpty);
      expect(x.timeToBeat, isNull);
      expect(x.price, isNull);
    });

    test('a full game payload comes through', () {
      final x = TitleExtras.fromJson({
        'screenshots': ['https://s/1.jpg'],
        'tags': [
          {'name': 'Comedy'},
          {'name': 'Isekai', 'rank': 90},
          {'name': ''},
        ],
        'languages': [
          {'name': 'Russian', 'interface': true, 'subtitles': true, 'audio': false},
        ],
        'time_to_beat': {'hastily': 8.5, 'normally': 10, 'completely': null, 'votes': 7},
        'price': '199 ₽',
        'price_discount_pct': 50,
        'metacritic': 95,
        'links': [
          {'kind': 'steam', 'label': 'Steam', 'url': 'https://store.steampowered.com/app/620'},
          {'kind': 'other', 'label': 'broken', 'url': 'not-a-url'},
        ],
        'related': [
          {'relation': 'DLC', 'title': 'Peer Review', 'media_type': 'game', 'id': 'igdb-11', 'source': 'igdb'},
          {'relation': 'Adaptation', 'title': 'Berserk', 'media_type': 'anime'},
        ],
      });
      expect(x.screenshots, hasLength(1));
      expect(x.tags.map((t) => t.name), ['Comedy', 'Isekai']); // blank tag dropped
      expect(x.tags[1].rank, 90);
      expect(x.languages.single.isRussian, isTrue);
      expect(x.timeToBeat!.normally, 10.0); // int from JSON becomes double
      expect(x.timeToBeat!.isEmpty, isFalse);
      expect(x.price, '199 ₽');
      expect(x.priceDiscountPct, 50);
      expect(x.links.map((l) => l.kind), ['steam']); // non-http url dropped
      expect(x.related[0].canOpenDirectly, isTrue);
      expect(x.related[1].canOpenDirectly, isFalse); // anime adaptation: search by title
    });

    test('book, manga and anime slices parse', () {
      final x = TitleExtras.fromJson({
        'pages': 592,
        'creators': [
          {'name': 'Kentarou Miura', 'name_ru': 'Кэнтаро Миура', 'role': 'Story & Art', 'bio': ' '},
        ],
        'reading_log': {'want': 1200, 'reading': 80, 'read': 900},
        'characters': [
          {'name': 'Guts', 'name_ru': 'Гатс', 'role': 'Main'},
        ],
        'studios': ['MAPPA'],
        'episodes': 12,
        'episodes_aired': 3,
        'next_episode_at': '2026-10-10T15:00:00.000+03:00',
      });
      expect(x.pages, 592);
      expect(x.creators.single.name, 'Kentarou Miura');
      expect(x.creators.single.bio, isNull); // whitespace-only bio is no bio
      expect(x.readingLog!.isEmpty, isFalse);
      expect(x.characters.single.role, 'Main');
      expect(x.studios, ['MAPPA']);
      expect(x.episodesAired, 3);
    });

    test('system requirements, platforms and the Deck verdict parse', () {
      final x = TitleExtras.fromJson({
        'requirements': {
          'minimum': [
            {'label': 'OS', 'value': 'Windows 10'},
            {'label': 'Memory', 'value': ''}, // empty value dropped
          ],
          'recommended': [],
        },
        'pc_platforms': ['windows', 'linux'],
        'steam_deck': 'verified',
      });
      expect(x.requirements!.minimum.map((r) => r.label), ['OS']);
      expect(x.requirements!.recommended, isEmpty);
      expect(x.requirements!.isEmpty, isFalse);
      expect(x.pcPlatforms, ['windows', 'linux']);
      expect(x.steamDeck, 'verified');
    });

    test('no requirements means the section has nothing to show', () {
      final x = TitleExtras.fromJson(<String, dynamic>{});
      expect(x.requirements, isNull);
      expect(x.steamDeck, isNull);
      expect(const SystemRequirements().isEmpty, isTrue);
    });

    test('an all-zero reading log counts as empty', () {
      expect(const ReadingLog(want: 0, reading: 0, read: 0).isEmpty, isTrue);
      expect(const TimeToBeat().isEmpty, isTrue);
    });
  });
}
