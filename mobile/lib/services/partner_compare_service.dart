import '../models/co_view_entry.dart';

/// One person's tally within a [PartnerCompareData] — either the caller
/// themselves or one other circle member.
class PartnerCompareEntry {
  final String username;
  final bool isSelf;
  // How many titles on the shared co-viewing list (planned + watched)
  // this person is the one who added — the only per-person signal
  // CoViewEntry actually carries (see its addedByUsername field). There
  // is no endpoint anywhere that exposes a partner's own personal
  // diary or ratings, so this comparison is built entirely from the
  // shared list both people already see, not from anything private.
  final int suggestedCount;
  final int movieCount;
  final int seriesCount;
  final int otherTypeCount; // anime/game/book/manga, lumped together

  const PartnerCompareEntry({
    required this.username,
    required this.isSelf,
    required this.suggestedCount,
    required this.movieCount,
    required this.seriesCount,
    required this.otherTypeCount,
  });
}

/// A couple or company's "who picks what" comparison, computed entirely
/// from the shared co-viewing list (see PartnerService.coViewing) — not
/// from a dedicated backend endpoint, since none exists for looking at
/// a partner's own personal stats (and, by design, never will without
/// their own explicit sharing — this only ever surfaces what both
/// people already see on the shared list). [people] always starts with
/// the caller, followed by every other circle member sorted by
/// suggestedCount, highest first.
class PartnerCompareData {
  final List<PartnerCompareEntry> people;
  final int watchedTogetherCount;
  final int plannedCount;

  const PartnerCompareData({
    required this.people,
    required this.watchedTogetherCount,
    required this.plannedCount,
  });

  PartnerCompareEntry get me => people.first;
  List<PartnerCompareEntry> get others => people.skip(1).toList();
}

class _Tally {
  int total = 0;
  int movies = 0;
  int series = 0;
  int other = 0;
}

class PartnerCompareService {
  const PartnerCompareService._();

  /// Builds the comparison from one already-fetched CoViewList — call
  /// sites (WrappedScreen, StatsScreen) both already know whether the
  /// account is linked (see PartnerStatus.linked) before reaching for
  /// this, since there's nothing to compare otherwise.
  static PartnerCompareData build({
    required String myUsername,
    required List<String> otherUsernames,
    required List<CoViewEntry> watched,
    required List<CoViewEntry> planned,
  }) {
    final tallies = <String, _Tally>{
      myUsername: _Tally(),
      for (final u in otherUsernames) u: _Tally(),
    };
    for (final e in [...watched, ...planned]) {
      final by = e.addedByUsername;
      // Entries with no recorded author (older data from before this
      // field existed) or an author outside the current circle just
      // don't count toward anyone — better to undercount than guess.
      final t = by == null ? null : tallies[by];
      if (t == null) continue;
      t.total++;
      switch (e.mediaType) {
        case 'movie':
          t.movies++;
          break;
        case 'series':
          t.series++;
          break;
        default:
          t.other++;
      }
    }
    PartnerCompareEntry entryFor(String username, bool isSelf) {
      final t = tallies[username]!;
      return PartnerCompareEntry(
        username: username,
        isSelf: isSelf,
        suggestedCount: t.total,
        movieCount: t.movies,
        seriesCount: t.series,
        otherTypeCount: t.other,
      );
    }

    final others = otherUsernames.map((u) => entryFor(u, false)).toList()
      ..sort((a, b) => b.suggestedCount.compareTo(a.suggestedCount));

    return PartnerCompareData(
      people: [entryFor(myUsername, true), ...others],
      watchedTogetherCount: watched.length,
      plannedCount: planned.length,
    );
  }
}
