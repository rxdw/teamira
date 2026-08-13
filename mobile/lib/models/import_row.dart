import 'media_item.dart';

/// One line from a pasted import (a plain title, or a row from a CSV
/// export) together with whatever the backend could resolve it to.
/// Mirrors `ImportRowOut` in backend/app/routers/imports.py.
///
/// [selected] and [status] are local-only — the client's own bookkeeping
/// for the review list, never sent as-is; see ImportService.commit.
class ImportRow {
  final String raw;
  final MediaItem? matched;
  final List<MediaItem> alternates;
  final int? year;
  final String? watchedAt;
  final int? rating;

  /// Which of [matched]/[alternates] this row currently points at — starts
  /// as the backend's own top pick. Null means "no match, not importable".
  MediaItem? chosen;

  /// Whether this row will actually be committed — defaults to true
  /// whenever there's a match, false otherwise (nothing to import).
  bool selected;

  /// "watched" | "watch_later" — defaults to whatever the person picked
  /// for the whole batch, but can be flipped per-row before committing.
  String status;

  ImportRow({
    required this.raw,
    required this.matched,
    required this.alternates,
    required this.year,
    required this.watchedAt,
    required this.rating,
    required this.status,
  })  : chosen = matched,
        selected = matched != null;

  factory ImportRow.fromJson(Map<String, dynamic> json, {required String defaultStatus}) {
    return ImportRow(
      raw: json['raw'] as String,
      matched: json['matched'] != null
          ? MediaItem.fromJson(json['matched'] as Map<String, dynamic>)
          : null,
      alternates: (json['alternates'] as List? ?? const [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      year: json['year'] as int?,
      watchedAt: json['watched_at'] as String?,
      rating: json['rating'] as int?,
      status: defaultStatus,
    );
  }
}

/// Result of POST /import/preview — the parsed+matched rows, plus what the
/// backend guessed the pasted text actually was ("csv" | "text"), mostly
/// useful for a small "looks like a CSV export" confirmation in the UI.
class ImportPreviewResult {
  final List<ImportRow> rows;
  final String sourceDetected;
  const ImportPreviewResult({required this.rows, required this.sourceDetected});
}

/// Result of POST /import/commit.
class ImportCommitResult {
  final int watchedCount;
  final int watchLaterCount;
  const ImportCommitResult({required this.watchedCount, required this.watchLaterCount});

  factory ImportCommitResult.fromJson(Map<String, dynamic> json) => ImportCommitResult(
        watchedCount: json['watched_count'] as int,
        watchLaterCount: json['watch_later_count'] as int,
      );
}
