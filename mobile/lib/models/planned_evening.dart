import 'media_item.dart';

/// One evening someone has planned ahead of time — pick a title, pick a
/// date, decide whether it's a co-viewing evening with a linked partner,
/// then "get a ticket" for it. Device-local only (see
/// [EveningPlanService]): this is a personal planning ritual, not
/// another synced list, so there's no backend row behind it — the date
/// and the co-viewing flag live only on this device, same as
/// [RitualPrefsService] and friends.
///
/// Several evenings can be planned at once — a whole season of "movie
/// nights" queued up in advance is a perfectly normal way to use this.
/// [EveningPlanService] holds all of them; [id] is what tells two
/// tickets apart (even for the same title planned twice on different
/// dates), and is what the "let it go" / "mark watched" actions target
/// so they only ever touch the one ticket they were opened from.
///
/// [hour]/[minute] are optional — most evenings only need a day ("an
/// evening", not a clock time, per the original design), but a specific
/// showtime or a co-viewing call time is common enough to be worth
/// carrying alongside the date rather than living only in a note
/// somewhere. Kept as plain ints rather than a `TimeOfDay` so this model
/// stays framework-light and trivially JSON-serializable, same as every
/// other field here.
class PlannedEvening {
  final String id;
  final String mediaId;
  final String source;
  final String mediaType;
  final String title;
  final String? posterUrl;
  final int? year;
  final DateTime date; // day precision — "an evening", not a clock time
  final int? hour; // 0-23, local time; null when no specific time was set
  final int? minute; // 0-59
  final bool coViewing;
  final String? partnerUsername; // snapshot only, for the ticket's own text
  final DateTime createdAt;

  PlannedEvening({
    String? id,
    required this.mediaId,
    required this.source,
    required this.mediaType,
    required this.title,
    this.posterUrl,
    this.year,
    required this.date,
    this.hour,
    this.minute,
    this.coViewing = false,
    this.partnerUsername,
    required this.createdAt,
  }) : id = id ?? '$mediaId-${createdAt.microsecondsSinceEpoch}';

  bool get hasTime => hour != null && minute != null;

  /// "7:30 PM" — formatted without needing a BuildContext (unlike
  /// `TimeOfDay.format`), since this gets read from plain model code in
  /// places like the card's reminder text just as often as from a
  /// widget's build method.
  String? get timeLabel {
    if (!hasTime) return null;
    final h = hour!;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = minute!.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  /// Calendar-day comparison, not a 24h window — someone who planned an
  /// evening for "today" should still see it as today's ticket at
  /// 11:58pm and at 12:02am the same way, not have it silently roll
  /// over mid-scroll.
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get isToday => _isSameDay(date, DateTime.now());

  bool get isTomorrow =>
      _isSameDay(date, DateTime.now().add(const Duration(days: 1)));

  /// Whole calendar days between today and the planned date — negative
  /// once the date's in the past, which the UI reads as "did you watch
  /// it?" rather than a countdown.
  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }

  bool get isPast => daysUntil < 0;

  MediaItem toMediaItem() => MediaItem(
        id: mediaId,
        mediaType: mediaType,
        externalIds: const ExternalIds(),
        title: LocalizedText(en: title),
        description: const LocalizedText(),
        posterUrl: posterUrl,
        year: year,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_id': mediaId,
        'source': source,
        'media_type': mediaType,
        'title': title,
        'poster_url': posterUrl,
        'year': year,
        'date': date.toIso8601String(),
        'hour': hour,
        'minute': minute,
        'co_viewing': coViewing,
        'partner_username': partnerUsername,
        'created_at': createdAt.toIso8601String(),
      };

  factory PlannedEvening.fromJson(Map<String, dynamic> json) => PlannedEvening(
        // Older, single-plan saves never had an id — the constructor's
        // default (mediaId + createdAt) fills it in the same way a
        // freshly-planned evening would get one.
        id: json['id'] as String?,
        mediaId: json['media_id'] as String,
        source: json['source'] as String,
        mediaType: json['media_type'] as String,
        title: json['title'] as String,
        posterUrl: json['poster_url'] as String?,
        year: json['year'] as int?,
        date: DateTime.parse(json['date'] as String),
        hour: json['hour'] as int?,
        minute: json['minute'] as int?,
        coViewing: json['co_viewing'] as bool? ?? false,
        partnerUsername: json['partner_username'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
