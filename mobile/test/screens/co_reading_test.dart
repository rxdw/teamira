// Unit tests for reading together (lib/screens/partner/room/reading/):
// the locator spelling the client shares with backend/app/co_reading.py, how
// an EPUB is read into blocks (the same bytes must always give the same
// chapters and paragraph numbers — that is what makes "chapter 4, paragraph
// 17" the same place on every phone), and what the room overlays on a page.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/models/circle_review.dart';
import 'package:teamira/models/co_view_room.dart';
import 'package:teamira/screens/partner/room/reading/book_source.dart';
import 'package:teamira/screens/partner/room/reading/reading_locator.dart';
import 'package:teamira/screens/partner/room/reading/reading_overlay.dart';

Uint8List _epub({
  required Map<String, String> chapters,
  List<String>? spine,
  String title = 'Тестовая книга',
  String? encryption,
}) {
  final a = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  if (encryption != null) add('META-INF/encryption.xml', encryption);
  final ids = chapters.keys.toList();
  final manifest = [
    for (var i = 0; i < ids.length; i++)
      '<item id="c$i" href="${ids[i]}" media-type="application/xhtml+xml"/>',
  ].join();
  final order = (spine ?? [for (var i = 0; i < ids.length; i++) 'c$i']).map((id) => '<itemref idref="$id"/>').join();
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<metadata><dc:title>$title</dc:title><dc:creator>Автор Авторов</dc:creator></metadata>'
        '<manifest>$manifest</manifest><spine>$order</spine></package>',
  );
  for (final e in chapters.entries) {
    add('OEBPS/${e.key}', e.value);
  }
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

String _page(String body) =>
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head><body>$body</body></html>';

RoomState _room({
  List<RoomParticipant> people = const [],
  List<RoomEvent> events = const [],
  List<RoomMark> marks = const [],
  String mode = 'own',
  String? lead,
  String? leader,
}) =>
    RoomState(
      id: 'r1',
      status: 'live',
      mediaId: 'file:abc',
      mediaType: 'book',
      source: 'file',
      playerKind: PlayerKind.parallel,
      isPlaying: false,
      positionMs: 0,
      serverNow: DateTime.utc(2026, 10, 2),
      controlSeq: 0,
      saveToShared: true,
      participants: people,
      events: events,
      lastSeq: events.isEmpty ? 0 : events.last.seq,
      voiceAvailable: false,
      activity: RoomActivity.read,
      readKind: ReadKind.epub,
      readMode: mode,
      leadLocator: lead,
      leadUserId: leader,
      marks: marks,
      createdAt: DateTime.utc(2026, 10, 2),
    );

RoomMark _mark(int seq, String kind, String locator, {String? user, String? body}) =>
    RoomMark(seq: seq, userId: user, kind: kind, locator: locator, body: body, positionMs: 410000);

RoomParticipant _person(String id, {bool you = false, bool present = true, String? locator}) => RoomParticipant(
      userId: id,
      username: id,
      isYou: you,
      isHost: false,
      joined: true,
      present: present,
      voiceOn: false,
      locator: locator,
    );

void main() {
  group('ReadLocator', () {
    test('spells places the way the server does', () {
      expect(const ReadLocator(ReadKind.epub, 3, 17).wire, 'c3:p17');
      expect(const ReadLocator(ReadKind.epub, 0).wire, 'c0:p0');
      expect(const ReadLocator(ReadKind.cbz, 42).wire, 'p42');
      expect(const ReadLocator(ReadKind.parallel, 5).wire, 'c5');
    });

    test('reads what the server sends, and refuses what does not fit the kind', () {
      expect(ReadLocator.tryParse(ReadKind.epub, 'c3:p7'), const ReadLocator(ReadKind.epub, 3, 7));
      expect(ReadLocator.tryParse(ReadKind.epub, 'c3'), const ReadLocator(ReadKind.epub, 3, 0));
      expect(ReadLocator.tryParse(ReadKind.cbz, 'p12'), const ReadLocator(ReadKind.cbz, 12));
      expect(ReadLocator.tryParse(ReadKind.parallel, 'c4'), const ReadLocator(ReadKind.parallel, 4));
      for (final bad in [null, '', 'p3', 'c3:p', 'x', 'c-1']) {
        expect(ReadLocator.tryParse(ReadKind.epub, bad), isNull, reason: '$bad');
      }
      expect(ReadLocator.tryParse(ReadKind.cbz, 'c3'), isNull);
      expect(ReadLocator.tryParse(ReadKind.parallel, 'c3:p1'), isNull);
    });

    test('round-trips', () {
      for (final l in const [
        ReadLocator(ReadKind.epub, 9, 120),
        ReadLocator(ReadKind.cbz, 0),
        ReadLocator(ReadKind.parallel, 31),
      ]) {
        expect(ReadLocator.tryParse(l.kind, l.wire), l);
      }
    });

    test('orders places in reading order', () {
      expect(const ReadLocator(ReadKind.epub, 2, 9).compareTo(const ReadLocator(ReadKind.epub, 3, 0)), lessThan(0));
      expect(const ReadLocator(ReadKind.epub, 3, 10).compareTo(const ReadLocator(ReadKind.epub, 3, 2)), greaterThan(0));
      expect(const ReadLocator(ReadKind.cbz, 4).compareTo(const ReadLocator(ReadKind.cbz, 4)), 0);
    });

    test('progress is a permille the server can scale', () {
      expect(permille(0), 0);
      expect(permille(0.5), 500);
      expect(permille(1), 1000);
      expect(permille(7), 1000);
      expect(permille(-1), 0);
      expect(percentOf(333), 33);
    });
  });

  group('reading an EPUB', () {
    final chapters = {
      'ch1.xhtml': _page('<h1>Глава первая</h1><p>Раз  два\n  три.</p><p>Второй <i>абзац</i> тут.</p>'),
      'cover.xhtml': _page('<img src="cover.jpg"/>'),
      'ch2.xhtml': _page('<h2>Глава вторая</h2><blockquote><p>Цитата.</p></blockquote><hr/><div><p>После черты.</p></div>'),
    };

    test('turns chapters into clean blocks, in spine order, skipping pages with no text', () {
      final r = parseEpubBytes(_epub(chapters: chapters));
      expect(r.error, isNull);
      final book = r.content!;
      expect(book.title, 'Тестовая книга');
      expect(book.author, 'Автор Авторов');
      expect(book.chapters.length, 2); // the cover has no text
      final first = book.chapters[0];
      expect(first.title, 'Глава первая');
      expect(first.blocks.map((b) => b.text).toList(), ['Глава первая', 'Раз два три.', 'Второй абзац тут.']);
      expect(first.blocks[0].isHeading, isTrue);
      final second = book.chapters[1];
      expect(second.blocks[1].quote, isTrue);
      expect(second.blocks[2].isBreak, isTrue);
      expect(second.blocks[3].text, 'После черты.');
    });

    test('the same bytes always give the same places', () {
      final bytes = _epub(chapters: chapters);
      final a = parseEpubBytes(bytes).content!;
      final b = parseEpubBytes(Uint8List.fromList(bytes)).content!;
      expect(a.chapters.length, b.chapters.length);
      for (var i = 0; i < a.chapters.length; i++) {
        expect(a.chapters[i].blocks.map((x) => x.text).toList(), b.chapters[i].blocks.map((x) => x.text).toList());
      }
    });

    test('follows the spine, not the manifest, and leaves out non-linear items', () {
      final bytes = _epub(chapters: chapters, spine: ['c2', 'c0']);
      final book = parseEpubBytes(bytes).content!;
      expect(book.chapters.first.title, 'Глава вторая');
      expect(book.chapters.last.title, 'Глава первая');
    });

    test('a protected book is refused kindly; font obfuscation is not protection', () {
      final drm = parseEpubBytes(_epub(
        chapters: chapters,
        encryption: '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<EncryptedData><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/></EncryptedData></encryption>',
      ));
      expect(drm.content, isNull);
      expect(drm.error, 'drm');

      final fonts = parseEpubBytes(_epub(
        chapters: chapters,
        encryption: '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<EncryptedData><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/></EncryptedData></encryption>',
      ));
      expect(fonts.error, isNull);
      expect(fonts.content, isNotNull);
    });

    test('not an epub, and an epub with no text, say so', () {
      expect(parseEpubBytes(Uint8List.fromList([1, 2, 3, 4])).error, 'broken');
      final empty = parseEpubBytes(_epub(chapters: {'c.xhtml': _page('<img src="a.jpg"/>')}));
      expect(empty.error, 'empty');
    });

    test('how far through the book a place is', () {
      final book = parseEpubBytes(_epub(chapters: chapters)).content!;
      expect(book.totalBlocks, 3 + 4);
      expect(book.fractionAt(0, 0), 0);
      expect(book.fractionAt(1, 0), closeTo(3 / 7, 1e-9));
      expect(book.fractionAt(99, 99), lessThan(1.0)); // clamped to the last block, not past the end
      expect(book.fractionAt(1, 3), closeTo(6 / 7, 1e-9));
    });
  });

  group('what the room adds to a page', () {
    test('notes sit at their place, and only people who are here and have a place show up', () {
      final s = _room(
        people: [
          _person('me', you: true, locator: 'c1:p1'),
          _person('anya', locator: 'c1:p4'),
          _person('gone', present: false, locator: 'c1:p4'),
          _person('nowhere'),
        ],
        marks: [
          _mark(2, 'margin', 'c1:p4', user: 'anya', body: 'вот это да'),
          _mark(3, 'margin', 'c2:p0', user: 'me', body: 'и тут'),
        ],
      );
      final o = ReadingOverlay.of(s);
      const here = ReadLocator(ReadKind.epub, 1, 4);
      expect(o.notesFor(here).map((m) => m.body).toList(), ['вот это да']);
      expect(o.notesFor(const ReadLocator(ReadKind.epub, 2, 0)).length, 1);
      expect(o.othersFor(here).map((p) => p.userId).toList(), ['anya']);
      expect(o.othersFor(const ReadLocator(ReadKind.epub, 1, 1)), isEmpty); // you are not "someone else"
    });

    test('a highlight is mine, theirs, or both', () {
      final s = _room(
        people: [_person('me', you: true), _person('anya')],
        marks: [
          _mark(1, 'highlight', 'c0:p1', user: 'me'),
          _mark(2, 'highlight', 'c0:p2', user: 'anya'),
          _mark(3, 'highlight', 'c0:p3', user: 'me'),
          _mark(4, 'highlight', 'c0:p3', user: 'anya'),
          _mark(5, 'margin', 'c0:p1', user: 'anya', body: 'заметка не подсветка'),
        ],
      );
      final o = ReadingOverlay.of(s);
      const p1 = ReadLocator(ReadKind.epub, 0, 1);
      const p2 = ReadLocator(ReadKind.epub, 0, 2);
      const p3 = ReadLocator(ReadKind.epub, 0, 3);
      expect([o.iHighlighted(p1), o.othersHighlighted(p1)], [true, false]);
      expect([o.iHighlighted(p2), o.othersHighlighted(p2)], [false, true]);
      expect([o.iHighlighted(p3), o.othersHighlighted(p3)], [true, true]);
      expect(o.highlightersFor(const ReadLocator(ReadKind.epub, 5, 5)), isEmpty);
      expect(o.notesFor(p1).length, 1); // the note does not count as a highlight
    });

    test('the glowing line exists only while reading aloud', () {
      const line = ReadLocator(ReadKind.epub, 2, 7);
      final own = ReadingOverlay.of(_room(mode: 'own', lead: 'c2:p7'));
      final together = ReadingOverlay.of(_room(mode: 'together', lead: 'c2:p7'));
      final aloud = ReadingOverlay.of(_room(mode: 'aloud', lead: 'c2:p7', leader: 'anya'));
      expect(own.isCursor(line), isFalse);
      expect(together.isCursor(line), isFalse);
      expect(aloud.isCursor(line), isTrue);
      expect(aloud.isCursor(const ReadLocator(ReadKind.epub, 2, 8)), isFalse);
    });

    test('the signature changes exactly when something worth redrawing does', () {
      final base = ReadingOverlay.of(_room(people: [_person('a', locator: 'c0:p0')]));
      final same = ReadingOverlay.of(_room(people: [_person('a', locator: 'c0:p0')]));
      final moved = ReadingOverlay.of(_room(people: [_person('a', locator: 'c0:p5')]));
      final noted = ReadingOverlay.of(_room(
        people: [_person('a', locator: 'c0:p0')],
        marks: [_mark(1, 'margin', 'c0:p0', user: 'a', body: 'x')],
      ));
      final lit = ReadingOverlay.of(_room(
        people: [_person('a', locator: 'c0:p0')],
        marks: [_mark(1, 'highlight', 'c0:p0', user: 'a')],
      ));
      final cursorA = ReadingOverlay.of(_room(mode: 'aloud', lead: 'c0:p1', leader: 'a'));
      final cursorB = ReadingOverlay.of(_room(mode: 'aloud', lead: 'c0:p2', leader: 'a'));
      expect(base.signature, same.signature);
      expect(base.signature, isNot(moved.signature));
      expect(base.signature, isNot(noted.signature));
      expect(noted.signature, isNot(lit.signature));
      expect(cursorA.signature, isNot(cursorB.signature));
    });
  });

  group('the room as the client sees it', () {
    Map<String, dynamic> base() => {
          'id': 'r', 'status': 'live', 'media_id': 'm', 'media_type': 'book', 'source': 'file',
          'player_kind': 'parallel', 'is_playing': false, 'position_ms': 250000, 'server_now': '2026-10-02T10:00:00',
          'control_seq': 2, 'save_to_shared': true, 'participants': [], 'events': [], 'last_seq': 0,
          'voice_available': false, 'created_at': '2026-10-02T10:00:00',
        };

    test('reading fields arrive, and a film room is still a film room', () {
      final reading = RoomState.fromJson({
        ...base(),
        'activity': 'read', 'read_kind': 'cbz', 'read_units': 180, 'read_mode': 'together', 'lead_locator': 'p42',
      });
      expect(reading.isReading, isTrue);
      expect(reading.isTogether, isTrue);
      expect(reading.isAloud, isFalse);
      expect(reading.hasSharedPlace, isTrue);
      expect(reading.readKind, ReadKind.cbz);
      expect(reading.readUnits, 180);
      expect(reading.leadLocator, 'p42');
      expect(reading.leadProgress, closeTo(0.25, 1e-9));

      final film = RoomState.fromJson({...base(), 'media_type': 'movie', 'source': 'tmdb', 'position_ms': 0});
      expect(film.isReading, isFalse);
      expect(film.isTogether, isFalse);
      expect(film.hasSharedPlace, isFalse);
      expect(film.readMode, 'own');
      expect(film.marks, isEmpty);
    });

    test('reading aloud is a shared place with one reader', () {
      final r = RoomState.fromJson({
        ...base(), 'activity': 'read', 'read_kind': 'epub', 'read_mode': 'aloud',
        'lead_locator': 'c1:p4', 'lead_user_id': 'anya',
      });
      expect(r.isAloud, isTrue);
      expect(r.isTogether, isFalse);
      expect(r.hasSharedPlace, isTrue);
      expect(r.leadUserId, 'anya');
    });

    test('marks arrive with the room — they do not depend on the events tail', () {
      final r = RoomState.fromJson({
        ...base(), 'activity': 'read', 'read_kind': 'epub',
        'marks': [
          {'seq': 3, 'user_id': 'a', 'kind': 'margin', 'locator': 'c1:p1', 'body': 'ого', 'quote': 'строчка', 'position_ms': 120000},
          {'seq': 9, 'user_id': 'b', 'kind': 'highlight', 'locator': 'c2:p0', 'position_ms': 300000},
        ],
      });
      expect(r.events, isEmpty);
      expect(r.marks.length, 2);
      expect(r.marks.first.isMargin, isTrue);
      expect(r.marks.first.quote, 'строчка');
      expect(r.marks.last.isHighlight, isTrue);
      expect(r.marks.last.positionMs, 300000);
    });

    test('a margin note carries its place and the line it is about', () {
      final e = RoomEvent.fromJson({
        'seq': 4, 'kind': 'margin', 'body': 'ого', 'locator': 'c3:p12', 'quote': 'строчка',
        'position_ms': 312000, 'created_at': '2026-10-02T10:00:00',
      });
      expect(e.isMargin, isTrue);
      expect(e.locator, 'c3:p12');
      expect(e.quote, 'строчка');
    });

    test('what setting a quote aside came to', () {
      final r = AlbumQuoteResult.fromJson({'created': true, 'added': true, 'chars_left': 231});
      expect(r.created, isTrue);
      expect(r.added, isTrue);
      expect(r.charsLeft, 231);
      expect(AlbumQuoteResult.fromJson({'created': false, 'added': false, 'chars_left': 5}).added, isFalse);
    });

    test('a book’s moment knows which chapter it was; a film’s does not', () {
      final book = ReviewMoment.fromJson({
        'position_ms': 410000, 'people': 2, 'shared': true, 'count': 3, 'top': '🖍', 'locator': 'c3:p4',
      });
      expect(book.locator, 'c3:p4');
      final film = ReviewMoment.fromJson({'position_ms': 61000, 'people': 1, 'shared': false, 'count': 1, 'top': '😂'});
      expect(film.locator, isNull);
    });
  });
}
