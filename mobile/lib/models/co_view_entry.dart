import 'media_item.dart';

/// Mirrors `CoViewEntryOut` in backend/app/schemas.py — one title on a
/// linked pair's shared co-viewing screen. Fed from three places: the
/// suggest heart on a title screen, a network Watch Together match, and a
/// local pass-the-phone Watch Together match — see
/// backend/app/routers/partner.py for the reasoning.
class CoViewEntry {
  final String id;
  final String mediaId;
  final String mediaType;
  final String source;
  final String? titleRu;
  final String? titleEn;
  final String? posterUrl;
  final int? year;
  final String status; // "planned" | "watched"
  final String? addedByUsername;
  final DateTime? watchedAt;
  final DateTime createdAt;
  // Set only when this entry came from "plan an evening"'s co-viewing
  // toggle (see PlannedEvening) — everything else this list can hold
  // (the suggest heart, a Watch Together match) has no schedule.
  final DateTime? scheduledDate;
  final int? scheduledHour;
  final int? scheduledMinute;

  const CoViewEntry({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.source,
    this.titleRu,
    this.titleEn,
    this.posterUrl,
    this.year,
    required this.status,
    this.addedByUsername,
    this.watchedAt,
    required this.createdAt,
    this.scheduledDate,
    this.scheduledHour,
    this.scheduledMinute,
  });

  bool get isWatched => status == 'watched';

  bool get hasSchedule => scheduledDate != null;

  /// "7:30 PM" — same formatting PlannedEvening.timeLabel uses, kept in
  /// sync so a scheduled evening reads identically whether it's shown
  /// from your own device-local ticket or from the shared co-viewing
  /// screen.
  String? get scheduledTimeLabel {
    if (scheduledHour == null || scheduledMinute == null) return null;
    final h = scheduledHour!;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = scheduledMinute!.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  String get displayTitle => (titleEn?.trim().isNotEmpty ?? false)
      ? titleEn!
      : (titleRu?.trim().isNotEmpty ?? false)
          ? titleRu!
          : '—';

  /// A minimal [MediaItem] built from the snapshot — enough to open the
  /// title screen, which backfills the rest itself.
  MediaItem toMediaItem() => MediaItem(
        id: mediaId,
        mediaType: mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(ru: titleRu, en: titleEn),
        description: const LocalizedText(),
        posterUrl: posterUrl,
        year: year,
        source: source,
      );

  factory CoViewEntry.fromJson(Map<String, dynamic> json) => CoViewEntry(
        id: json['id'] as String,
        mediaId: json['media_id'] as String,
        mediaType: json['media_type'] as String,
        source: json['source'] as String,
        titleRu: json['title_ru'] as String?,
        titleEn: json['title_en'] as String?,
        posterUrl: json['poster_url'] as String?,
        year: json['year'] as int?,
        status: json['status'] as String,
        addedByUsername: json['added_by_username'] as String?,
        watchedAt: json['watched_at'] != null
            ? DateTime.parse(json['watched_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        scheduledDate: json['scheduled_date'] != null
            ? DateTime.parse(json['scheduled_date'] as String)
            : null,
        scheduledHour: json['scheduled_hour'] as int?,
        scheduledMinute: json['scheduled_minute'] as int?,
      );
}

/// Mirrors `CoViewOut` — the whole co-viewing screen's data in one call:
/// both usernames (for the header) plus the planned/watched split.
class CoViewList {
  final String myUsername;
  final String? partnerUsername;
  // Everyone else in the circle besides the caller — a couple has
  // exactly one entry here (same person [partnerUsername] names), a
  // company has two or more. Prefer this over [partnerUsername] for
  // anything that needs to show (or count) who's actually in the
  // circle — [partnerUsername] only ever names the first of them.
  final List<String> otherUsernames;
  final List<CoViewEntry> planned;
  final List<CoViewEntry> watched;

  const CoViewList({
    required this.myUsername,
    this.partnerUsername,
    this.otherUsernames = const [],
    required this.planned,
    required this.watched,
  });

  factory CoViewList.fromJson(Map<String, dynamic> json) => CoViewList(
        myUsername: json['my_username'] as String,
        partnerUsername: json['partner_username'] as String?,
        otherUsernames: (json['other_usernames'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        planned: (json['planned'] as List)
            .map((e) => CoViewEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        watched: (json['watched'] as List)
            .map((e) => CoViewEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
