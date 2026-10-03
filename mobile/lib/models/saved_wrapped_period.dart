import 'package:flutter/material.dart' show DateTimeRange;

/// A "свой период" the person named once and kept — see
/// SavedPeriodsService, which persists a list of these locally (there's
/// no backend endpoint for them, same as CustomWrappedService's own
/// locally-computed summaries). [id] is a local-only identifier, never
/// sent anywhere.
class SavedWrappedPeriod {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final DateTime savedAt;

  const SavedWrappedPeriod({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.savedAt,
  });

  DateTimeRange get range => DateTimeRange(start: start, end: end);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'saved_at': savedAt.toIso8601String(),
      };

  factory SavedWrappedPeriod.fromJson(Map<String, dynamic> json) =>
      SavedWrappedPeriod(
        id: json['id'] as String,
        title: json['title'] as String,
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
        savedAt: DateTime.parse(json['saved_at'] as String),
      );
}
