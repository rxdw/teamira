// Unit tests for utils/release_genres.dart — the genre filter behind the
// release calendar.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/media_item.dart';
import 'package:teamira/models/release_calendar_item.dart';
import 'package:teamira/utils/release_genres.dart';

ReleaseCalendarItem _item(String title, String type, List<String> genres) =>
    ReleaseCalendarItem(
      source: type == 'anime' ? 'shikimori' : 'tmdb',
      mediaType: type,
      releaseDate: '2026-10-01',
      title: LocalizedText(en: title),
      genres: genres,
    );

void main() {
  final horror = _item('a', 'movie', ['Horror', 'Thriller']);
  final comedy = _item('b', 'movie', ['Comedy']);
  final anime = _item('c', 'anime', ['Action', 'Comedy']);
  final bare = _item('d', 'anime', []);
  final all = [horror, comedy, anime, bare];

  test('counts every genre across the pool', () {
    expect(releaseGenreCounts(all), {'Horror': 1, 'Thriller': 1, 'Comedy': 2, 'Action': 1});
  });

  test('any-of match, empty pick means no filter', () {
    expect(filterReleasesByGenres(all, {}), all);
    expect(filterReleasesByGenres(all, {'Comedy'}), [comedy, anime]);
    expect(filterReleasesByGenres(all, {'Horror', 'Action'}), [horror, anime]);
  });

  test('a pick the pool does not contain is ignored, not an empty screen', () {
    expect(filterReleasesByGenres([horror, comedy], {'Shooter'}), [horror, comedy]);
    expect(activeReleaseGenres([horror], {'Horror', 'Shooter'}), {'Horror'});
  });

  test('no-genre releases drop out while a filter is on', () {
    expect(filterReleasesByGenres(all, {'Comedy'}).contains(bare), isFalse);
  });

  test('allGenres reads either the row or the MediaItem', () {
    expect(anime.allGenres, ['Action', 'Comedy']);
  });
}
