import 'circle_review.dart';
import 'pair_album.dart' show AlbumPerson;

/// Client mirror of `GET /partner/reviews/book`
/// (backend/app/routers/circle_review.py): everything the PDF "book of your
/// evenings" is made of, in one response.
///
/// What may go in is decided by the server — only opened reviews the person
/// took part in, with something written in them, and the moments of room
/// evenings already computed. The classes here only carry that and do the
/// arithmetic the book's "at a glance" page needs.

/// The evening's calendar day: the day it was watched, or — for a review the
/// server somehow sent without one — the day it was created.
extension CircleReviewDay on CircleReview {
  DateTime get day => watchedOn ?? createdAt;
}

/// Oldest evening first; two evenings on the same day keep the order they
/// were opened in.
int compareEvenings(CircleReview a, CircleReview b) {
  final byDay = DateTime(a.day.year, a.day.month, a.day.day)
      .compareTo(DateTime(b.day.year, b.day.month, b.day.day));
  return byDay != 0 ? byDay : a.createdAt.compareTo(b.createdAt);
}

class EveningsBook {
  /// Everyone in the circle today, the signed-in person flagged by
  /// [AlbumPerson.isYou].
  final List<AlbumPerson> people;

  /// Oldest evening first.
  final List<CircleReview> reviews;

  /// The circle has more evenings than one book holds; the oldest were left
  /// out.
  final bool truncated;

  const EveningsBook({
    required this.people,
    required this.reviews,
    this.truncated = false,
  });

  bool get isEmpty => reviews.isEmpty;

  /// "Аня и Миша" / "Аня, Миша и Оля" — the names on the cover, in the
  /// order the circle lists them.
  List<String> get names => [for (final p in people) p.name];

  factory EveningsBook.fromJson(Map<String, dynamic> j) {
    final reviews = ((j['reviews'] as List?) ?? const [])
        .map((e) => CircleReview.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort(compareEvenings);
    return EveningsBook(
      people: ((j['people'] as List?) ?? const [])
          .map((e) => AlbumPerson.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviews: reviews,
      truncated: j['truncated'] == true,
    );
  }
}

class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}

class PersonAverage {
  final AlbumPerson person;

  /// The mean of every rating this person left in the book.
  final double average;

  /// How many evenings that mean is made of.
  final int rated;

  const PersonAverage({required this.person, required this.average, required this.rated});
}

/// The numbers on the book's "at a glance" page. Pure arithmetic over the
/// reviews the server sent — nothing here is stored anywhere.
class EveningsBookStats {
  final int evenings;
  final DateTime? first;
  final DateTime? last;

  /// The mean of the evenings' own averages (each evening counts once, however
  /// many people rated it). Null when nothing was rated.
  final double? average;

  /// How the evenings sat by the server's verdict (`unison` / `close` /
  /// `split`); `solo` evenings, with fewer than two ratings, are in none.
  final int unison;
  final int close;
  final int split;

  /// The evening with the highest shared average (the latest one wins a tie).
  final CircleReview? best;

  /// The evening whose ratings were furthest apart — only when that is a real
  /// disagreement, i.e. the verdict is `split`.
  final CircleReview? mostDisputed;

  /// The words the circle reached for most, most-used first.
  final List<TagCount> topTags;

  /// Each person's own mean rating, in the circle's order. Only people who
  /// rated at least one evening.
  final List<PersonAverage> perPerson;

  /// Evenings that have a moments timeline, and how many of its moments were
  /// shared by two or more people.
  final int momentEvenings;
  final int sharedMoments;

  const EveningsBookStats({
    required this.evenings,
    this.first,
    this.last,
    this.average,
    this.unison = 0,
    this.close = 0,
    this.split = 0,
    this.best,
    this.mostDisputed,
    this.topTags = const [],
    this.perPerson = const [],
    this.momentEvenings = 0,
    this.sharedMoments = 0,
  });

  /// How many tags the "your words" strip shows at most.
  static const topTagsLimit = 8;

  /// A spread at or past this many points is a real disagreement — the same
  /// line the server draws for the `split` verdict.
  static const splitSpread = 4;

  factory EveningsBookStats.of(EveningsBook book) {
    final reviews = [...book.reviews]..sort(compareEvenings);

    final averages = <double>[];
    var unison = 0, close = 0, split = 0;
    CircleReview? best;
    double bestAverage = -1;
    CircleReview? disputed;
    int widest = splitSpread - 1;
    final ratingsByPerson = <String, List<int>>{};
    final tagCounts = <String, int>{};
    final tagShown = <String, String>{};
    var momentEvenings = 0;
    var sharedMoments = 0;

    for (final r in reviews) {
      final summary = r.summary;
      if (summary != null) {
        final avg = summary.average;
        if (avg != null) {
          averages.add(avg);
          // `>=` so that, walking oldest to newest, the latest of equals wins.
          if (avg >= bestAverage) {
            bestAverage = avg;
            best = r;
          }
        }
        switch (summary.verdict) {
          case 'unison':
            unison++;
          case 'close':
            close++;
          case 'split':
            split++;
        }
        final spread = summary.spread;
        if (summary.verdict == 'split' && spread != null && spread > widest) {
          widest = spread;
          disputed = r;
        }
      }

      for (final person in r.people) {
        final rating = person.rating;
        if (rating != null) {
          ratingsByPerson.putIfAbsent(person.userId, () => <int>[]).add(rating);
        }
        for (final raw in person.tags) {
          final shown = raw.trim();
          if (shown.isEmpty) continue;
          final key = shown.toLowerCase();
          tagCounts[key] = (tagCounts[key] ?? 0) + 1;
          tagShown.putIfAbsent(key, () => shown);
        }
      }

      final moments = r.moments;
      if (moments != null && moments.isNotEmpty) {
        momentEvenings++;
        sharedMoments += moments.where((m) => m.shared).length;
      }
    }

    final tags = tagCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    final perPerson = <PersonAverage>[];
    for (final person in book.people) {
      final ratings = ratingsByPerson[person.userId];
      if (ratings == null || ratings.isEmpty) continue;
      perPerson.add(PersonAverage(
        person: person,
        average: ratings.reduce((a, b) => a + b) / ratings.length,
        rated: ratings.length,
      ));
    }

    return EveningsBookStats(
      evenings: reviews.length,
      first: reviews.isEmpty ? null : reviews.first.day,
      last: reviews.isEmpty ? null : reviews.last.day,
      average: averages.isEmpty ? null : averages.reduce((a, b) => a + b) / averages.length,
      unison: unison,
      close: close,
      split: split,
      best: best,
      mostDisputed: disputed,
      topTags: [
        for (final e in tags.take(topTagsLimit)) TagCount(tagShown[e.key]!, e.value),
      ],
      perPerson: perPerson,
      momentEvenings: momentEvenings,
      sharedMoments: sharedMoments,
    );
  }
}
