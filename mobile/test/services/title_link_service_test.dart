// Unit tests for services/title_link_service.dart's extractFromUri — the
// pure, no-IO piece of the shared-title deep link flow, same reasoning
// as referral_link_service_test.dart for extractFromUri there.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/services/title_link_service.dart';

void main() {
  group('TitleLinkService.extractFromUri', () {
    test('extracts id/type/source/title from a custom-scheme link', () {
      final uri = Uri.parse(
        'seenly://title?type=series&id=tmdb-1399&source=tmdb&title=Game%20of%20Thrones',
      );
      final link = TitleLinkService.extractFromUri(uri);
      expect(link, isNotNull);
      expect(link!.mediaId, 'tmdb-1399');
      expect(link.mediaType, 'series');
      expect(link.source, 'tmdb');
      expect(link.title, 'Game of Thrones');
    });

    test('extracts from the https App Link form the same way', () {
      final uri = Uri.parse('https://seenly.app/t?type=movie&id=tmdb-603&source=tmdb&title=The%20Matrix');
      final link = TitleLinkService.extractFromUri(uri);
      expect(link, isNotNull);
      expect(link!.mediaId, 'tmdb-603');
      expect(link.mediaType, 'movie');
      expect(link.source, 'tmdb');
    });

    test('title is optional — an empty string, not null, when absent', () {
      final uri = Uri.parse('seenly://title?type=movie&id=tmdb-603&source=tmdb');
      final link = TitleLinkService.extractFromUri(uri);
      expect(link, isNotNull);
      expect(link!.title, '');
    });

    test('missing source returns null — a link that would just 404 once used', () {
      final uri = Uri.parse('seenly://title?type=movie&id=tmdb-603');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });

    test('missing id returns null', () {
      final uri = Uri.parse('seenly://title?type=movie&source=tmdb');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });

    test('missing type returns null', () {
      final uri = Uri.parse('seenly://title?id=tmdb-603&source=tmdb');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });

    test('an empty source is treated as absent, not as an empty value', () {
      final uri = Uri.parse('seenly://title?type=movie&id=tmdb-603&source=');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });

    test('a referral-style link (no id/type/source at all) returns null', () {
      final uri = Uri.parse('seenly://invite?code=ABC123');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });

    test('a totally unrelated URL returns null', () {
      final uri = Uri.parse('https://seenly.app/about');
      expect(TitleLinkService.extractFromUri(uri), isNull);
    });
  });
}
