import '../models/import_row.dart';
import 'api_client.dart';

/// Bulk "bring your history over" — pastes a plain title list or a CSV
/// export (Letterboxd and similar services all export the same basic
/// shape) and resolves each line against the app's own catalog before
/// anything is actually written. See backend/app/routers/imports.py.
class ImportService {
  final ApiClient _client;
  ImportService(this._client);

  /// Parses+matches [text] without writing anything yet. [defaultStatus]
  /// ("watched" | "watch_later") is purely local bookkeeping for the
  /// returned rows — the backend itself is status-agnostic at this step.
  ///
  /// A generous timeout: this does one catalog search per pasted line on
  /// the backend, so a long paste genuinely takes a while.
  Future<ImportPreviewResult> preview(String text, {required String defaultStatus}) async {
    final json = await _client.post(
      '/import/preview',
      body: {'text': text},
      timeout: const Duration(seconds: 90),
    ) as Map<String, dynamic>;
    final rows = (json['rows'] as List)
        .map((e) => ImportRow.fromJson(e as Map<String, dynamic>, defaultStatus: defaultStatus))
        .toList();
    return ImportPreviewResult(rows: rows, sourceDetected: json['source_detected'] as String);
  }

  Future<ImportCommitResult> commit(List<ImportRow> rows) async {
    final selected = rows.where((r) => r.selected && r.chosen != null).toList();
    final json = await _client.post(
      '/import/commit',
      body: {
        'rows': [
          for (final r in selected)
            {
              'item': r.chosen!.toJson(),
              'status': r.status,
              if (r.watchedAt != null) 'watched_at': r.watchedAt,
              if (r.rating != null) 'rating': r.rating,
            },
        ],
      },
      timeout: const Duration(seconds: 30),
    ) as Map<String, dynamic>;
    return ImportCommitResult.fromJson(json);
  }
}
